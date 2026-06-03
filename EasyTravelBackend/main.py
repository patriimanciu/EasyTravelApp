"""
FastAPI entrypoint: multimodal extraction aligned with thesis Chapter 3 (FR-02–FR-05, NFR-02, NFR-07).

Pipeline: ingest media → ASR segments → optional frame OCR → LLM consolidation → structured locations.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

from consolidate import (
    CONSOLIDATION_SYSTEM_PROMPT,
    PROMPT_TEMPLATE_VERSION,
    build_consolidation_user_message,
    run_artifact_summary,
)
from location_postprocess import strip_redundant_anchor_city_rows
from media_ingest import cleanup_bundle, download_media_bundle
from ocr_service import extract_text_from_video
from ttdp_routing import (
    StopSpec,
    normalize_clustering_method,
    normalize_osrm_profile,
    plan_ttdp_itinerary,
    planning_fields_from_visit_priority,
)
from whisper_service import empty_asr_result, format_asr_block, transcribe_local_file

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Travel Itinerary Extractor API")

CONSOLIDATION_MODEL = os.environ.get("OPENAI_CONSOLIDATION_MODEL", "gpt-4o-mini")
OCR_SAMPLE_SECONDS = float(os.environ.get("OCR_SAMPLE_SECONDS", "2"))
OCR_MAX_FRAMES = int(os.environ.get("OCR_MAX_FRAMES", "45"))


def get_openai_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="OPENAI_API_KEY is not set on the server.",
        )
    return OpenAI(api_key=api_key)


class VideoRequest(BaseModel):
    url: str


class Location(BaseModel):
    """FR-08 interchange subset + thesis provenance hints."""

    name: str
    category: str
    city: str
    address: str | None = Field(default=None, description="Street or venue address if stated in modalities.")
    phone_number: str | None = Field(default=None, description="Phone as shown in video/caption/OCR.")
    url: str | None = Field(default=None, description="Official or clearly stated website URL.")
    opening_hours: str | None = Field(default=None, description="Opening hours/days if stated.")
    source_modalities: list[str] = Field(
        default_factory=list,
        description='Subset of "asr", "ocr", "caption" when supported.',
    )
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)


class LocationExtraction(BaseModel):
    locations: list[Location]


class RouteStop(BaseModel):
    """One POI vertex in the TTDP shortcut graph (thesis Chapter 2.3)."""

    id: str
    latitude: float
    longitude: float
    visit_priority: int = Field(
        default=3,
        ge=1,
        le=5,
        description="1=low/if time … 5=must see. Drives mandatory flag, drop order, and day clustering.",
    )
    weight: float = Field(
        default=1.0,
        ge=0.0,
        description="Optional override; usually derived from visit_priority.",
    )
    mandatory: bool = Field(
        default=False,
        description="Optional override; priority 4–5 sets mandatory unless explicitly false.",
    )
    service_time_seconds: float = Field(default=0.0, ge=0.0, description="Time spent at the stop (visit duration).")


def _resolve_number_of_days_for_planning(
    requested: int,
    trip_start: datetime | None,
    trip_end: datetime | None,
) -> tuple[int, str]:
    """
    When both trip bounds are set and end >= start, use inclusive calendar day count
    (same rule as the iOS trip editor). That count drives k-means clusters = days.
    Otherwise use the client-supplied ``number_of_days``.
    """
    req = max(1, min(365, int(requested)))
    if trip_start is not None and trip_end is not None:
        d0 = trip_start.date()
        d1 = trip_end.date()
        if d1 < d0:
            return req, "invalid_trip_bounds_used_request"
        span = (d1 - d0).days + 1
        return max(1, min(365, span)), "trip_calendar_bounds"
    return req, "number_of_days_request"


class PlanItineraryRequest(BaseModel):
    """Chapter 2.3–2.4: clustering + matrix + NN/2-opt."""

    start_latitude: float
    start_longitude: float
    stops: list[RouteStop]
    number_of_days: int = Field(default=1, ge=1, le=365)
    trip_start: datetime | None = Field(
        default=None,
        description="Trip start (ISO-8601). With trip_end, sets how many clusters/days k-means uses.",
    )
    trip_end: datetime | None = Field(
        default=None,
        description="Trip end (ISO-8601). Inclusive calendar span with trip_start.",
    )
    daily_budget_seconds: float | None = Field(
        default=None,
        ge=0.0,
        description="Hard cap per day (travel + service). Optional stops may be dropped to satisfy it.",
    )
    return_to_start: bool = Field(
        default=False,
        description="If true, close the tour back to the (virtual) start of that day.",
    )
    travel_model: str = Field(
        default="haversine",
        description='Use "haversine" (crow-flight at average_speed_kmh) or "osrm" (OSRM table + route; profile from osrm_profile, default foot).',
    )
    average_speed_kmh: float = Field(default=15.0, ge=0.5, le=300.0)
    clustering_seed: int = Field(default=42)
    clustering_method: str = Field(
        default="k_means",
        description='Spatial partition per day: "k_means" or "dbscan" (density-based, then adjusted to day count).',
    )
    dbscan_eps_m: float = Field(
        default=2500.0,
        ge=100.0,
        le=50_000.0,
        description="DBSCAN neighbourhood radius in metres (only if clustering_method=dbscan).",
    )
    dbscan_min_samples: int = Field(
        default=2,
        ge=1,
        le=50,
        description="DBSCAN min points per cluster (only if clustering_method=dbscan).",
    )
    priority_rebalance: bool = Field(
        default=True,
        description="After spatial clustering, spread must-see POIs across days (does not change k-means/DBSCAN family).",
    )
    accommodation_latitude: float | None = Field(
        default=None,
        ge=-90.0,
        le=90.0,
        description="Hotel / stay latitude. With accommodation_longitude, each day routes from hub → POIs → hub.",
    )
    accommodation_longitude: float | None = Field(
        default=None,
        ge=-180.0,
        le=180.0,
        description="Hotel / stay longitude. Pair with accommodation_latitude.",
    )
    osrm_profile: str = Field(
        default="foot",
        description='OSRM routing profile for table + map geometry: "foot" (walking), "driving", or "bike".',
    )


class DayPlanResponse(BaseModel):
    day_index: int
    ordered_stop_ids: list[str]
    total_travel_seconds: float
    total_service_seconds: float
    total_seconds: float
    within_budget: bool
    dropped_stop_ids: list[str]
    route_polyline: list[list[float]] | None = Field(
        default=None,
        description="[[lat, lon], ...] OSRM path geometry (profile from request osrm_profile) for this day (start → stops [→ start]).",
    )


class PlanItineraryResponse(BaseModel):
    days: list[DayPlanResponse]
    metadata: dict


def _artifact_base_path(art_root: str, run_id: str, started: str) -> str:
    safe_ts = started.replace(":", "-")
    return os.path.join(art_root, f"{run_id}_{safe_ts}")


@app.post("/api/plan-itinerary", response_model=PlanItineraryResponse)
async def plan_itinerary(body: PlanItineraryRequest) -> PlanItineraryResponse:
    """
    TTDP-style routing (thesis Chapter 2.3–2.4): spatial clustering (k-means or DBSCAN), travel-time matrix, NN + 2-opt.
    """
    if not body.stops:
        return PlanItineraryResponse(
            days=[],
            metadata={
                "clustering": normalize_clustering_method(body.clustering_method),
                "priority_rebalance": "true" if body.priority_rebalance else "false",
                "routing": "nearest_neighbor_plus_2opt",
                "graph": "complete_directed_travel_time",
                "travel_model": body.travel_model,
                "osrm_profile": normalize_osrm_profile(body.osrm_profile),
            },
        )

    ids = [s.id.strip() for s in body.stops]
    if any(not x for x in ids):
        raise HTTPException(status_code=400, detail="Each stop must include a non-empty id.")
    if len(set(ids)) != len(ids):
        raise HTTPException(status_code=400, detail="Stop ids must be unique.")

    specs: list[StopSpec] = []
    for s in body.stops:
        w_plan, mand_plan = planning_fields_from_visit_priority(s.visit_priority)
        weight = float(s.weight) if s.weight != 1.0 else w_plan
        mandatory = bool(s.mandatory) or mand_plan
        specs.append(
            StopSpec(
                id=s.id.strip(),
                lat=s.latitude,
                lon=s.longitude,
                weight=weight,
                mandatory=mandatory,
                service_seconds=s.service_time_seconds,
                priority=s.visit_priority,
            )
        )

    effective_days, days_source = _resolve_number_of_days_for_planning(
        body.number_of_days,
        body.trip_start,
        body.trip_end,
    )

    days, meta = await asyncio.to_thread(
        plan_ttdp_itinerary,
        specs,
        body.start_latitude,
        body.start_longitude,
        number_of_days=effective_days,
        daily_budget_seconds=body.daily_budget_seconds,
        return_to_start=body.return_to_start,
        travel_model=body.travel_model,
        average_speed_kmh=body.average_speed_kmh,
        clustering_seed=body.clustering_seed,
        clustering_method=body.clustering_method,
        dbscan_eps_m=body.dbscan_eps_m,
        dbscan_min_samples=body.dbscan_min_samples,
        priority_rebalance=body.priority_rebalance,
        accommodation_latitude=body.accommodation_latitude,
        accommodation_longitude=body.accommodation_longitude,
        osrm_profile=body.osrm_profile,
    )

    meta = {
        **meta,
        "number_of_days_effective": str(effective_days),
        "number_of_days_source": days_source,
        "number_of_days_client": str(body.number_of_days),
    }

    return PlanItineraryResponse(
        days=[
            DayPlanResponse(
                day_index=d.day_index,
                ordered_stop_ids=d.ordered_stop_ids,
                total_travel_seconds=d.total_travel_seconds,
                total_service_seconds=d.total_service_seconds,
                total_seconds=d.total_seconds,
                within_budget=d.within_budget,
                dropped_stop_ids=d.dropped_stop_ids,
                route_polyline=(
                    [[float(lat), float(lon)] for lat, lon in d.route_polyline_lat_lon]
                    if d.route_polyline_lat_lon
                    else None
                ),
            )
            for d in days
        ],
        metadata=meta,
    )


@app.post("/api/process-video")
async def process_video(request: VideoRequest):
    """
    Multimodal extraction: ASR + OCR + captions → consolidated POI-like locations (FR-05).
    """
    run_id = uuid.uuid4().hex[:12]
    started = datetime.now(timezone.utc).isoformat()
    bundle = None
    try:
        bundle = await download_media_bundle(request.url)
        if not bundle.video_path and not bundle.audio_path:
            raise HTTPException(status_code=400, detail="No downloadable media path.")

        logger.info("[%s] Starting multimodal pipeline", run_id)

        whisper_lang = os.environ.get("WHISPER_LANGUAGE", "en")
        asr_path = bundle.asr_path()
        if asr_path:
            try:
                asr = await asyncio.to_thread(transcribe_local_file, asr_path, language=whisper_lang)
            except Exception as e:
                logger.warning("[%s] ASR failed (graceful degrade NFR-02): %s", run_id, e)
                asr = empty_asr_result(note=str(e))
        else:
            logger.info("[%s] No audio for ASR — OCR and caption only (NFR-02).", run_id)
            asr = empty_asr_result(note="video has no audio track and separate audio download failed")

        ocr_strings: list[str] = []
        if bundle.video_path:
            try:
                ocr_lang = os.environ.get("OCR_TESS_LANG", "eng")

                def _run_ocr() -> list:
                    return extract_text_from_video(
                        bundle.video_path,
                        sample_interval_seconds=OCR_SAMPLE_SECONDS,
                        max_frames=OCR_MAX_FRAMES,
                        tesseract_lang=ocr_lang,
                    )

                ocr_result = await asyncio.to_thread(_run_ocr)
                ocr_strings = [x.text for x in ocr_result]
                logger.info("[%s] OCR stage done: %d line(s)", run_id, len(ocr_strings))
            except Exception as e:
                logger.warning("[%s] OCR stage failed (graceful degrade NFR-02): %s", run_id, e)
        else:
            logger.info("[%s] Audio-only bundle — OCR skipped (NFR-02).", run_id)

        caption = (bundle.description or "").strip()
        transcript = (asr.get("plain_text") or "").strip()
        if not transcript and not ocr_strings and not caption:
            raise HTTPException(
                status_code=400,
                detail="No usable text from ASR, OCR, or caption metadata.",
            )

        asr_block = format_asr_block(asr)
        user_content = build_consolidation_user_message(
            title=bundle.title,
            description=bundle.description,
            asr_block=asr_block,
            ocr_lines=ocr_strings,
        )

        summary = run_artifact_summary(
            asr=asr,
            ocr_count=len(ocr_strings),
            ocr_interval=OCR_SAMPLE_SECONDS,
            had_video=bundle.video_path is not None,
        )

        logger.info(
            "[%s] run_started=%s prompt_template=%s consolidation_model=%s provenance=%s",
            run_id,
            started,
            PROMPT_TEMPLATE_VERSION,
            CONSOLIDATION_MODEL,
            json.dumps(summary),
        )

        art_root = os.environ.get("EXTRACTION_ARTIFACTS_DIR")
        base_path: str | None = None
        if art_root:
            try:
                os.makedirs(art_root, exist_ok=True)
                base_path = _artifact_base_path(art_root, run_id, started)
                with open(base_path + "_asr_segments.json", "w", encoding="utf-8") as f:
                    json.dump(asr.get("segments") or [], f, indent=2)
                with open(base_path + "_ocr_lines.json", "w", encoding="utf-8") as f:
                    json.dump(ocr_strings, f, indent=2)
                with open(base_path + "_consolidation_input.txt", "w", encoding="utf-8") as f:
                    f.write(user_content)
            except OSError as e:
                logger.warning("[%s] artifact persist failed (optional FR-13): %s", run_id, e)
                base_path = None

        client = get_openai_client()
        completion = client.beta.chat.completions.parse(
            model=CONSOLIDATION_MODEL,
            messages=[
                {"role": "system", "content": CONSOLIDATION_SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            response_format=LocationExtraction,
        )

        msg = completion.choices[0].message
        refusal = getattr(msg, "refusal", None)
        if refusal:
            raise HTTPException(status_code=502, detail=f"LLM refusal: {refusal}")

        parsed = msg.parsed
        if parsed is None:
            raise HTTPException(status_code=502, detail="LLM returned no structured locations.")

        filtered = strip_redundant_anchor_city_rows(
            parsed.locations,
            title=bundle.title,
            description=bundle.description,
        )
        if len(filtered) != len(parsed.locations):
            logger.info("[%s] Anchor-city postprocess: %d → %d rows", run_id, len(parsed.locations), len(filtered))
        parsed = parsed.model_copy(update={"locations": filtered})

        if base_path:
            try:
                with open(base_path + "_consolidated.json", "w", encoding="utf-8") as f:
                    json.dump(parsed.model_dump(), f, indent=2)
            except OSError as e:
                logger.warning("[%s] consolidated artifact write failed: %s", run_id, e)

        logger.info("[%s] Pipeline OK — %d location(s)", run_id, len(parsed.locations))
        return parsed

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("[%s] Pipeline error", run_id)
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}") from e
    finally:
        if bundle is not None:
            cleanup_bundle(bundle)
