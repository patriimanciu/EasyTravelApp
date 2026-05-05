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
from whisper_service import format_asr_block, transcribe_local_file

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


def _artifact_base_path(art_root: str, run_id: str, started: str) -> str:
    safe_ts = started.replace(":", "-")
    return os.path.join(art_root, f"{run_id}_{safe_ts}")


@app.post("/api/process-video")
async def process_video(request: VideoRequest):
    """
    Multimodal extraction: ASR + OCR + captions → consolidated POI-like locations (FR-05).
    """
    run_id = uuid.uuid4().hex[:12]
    started = datetime.now(timezone.utc).isoformat()
    bundle = await download_media_bundle(request.url)

    try:
        media_path = bundle.video_path or bundle.audio_path
        if not media_path:
            raise HTTPException(status_code=400, detail="No downloadable media path.")

        logger.info("[%s] Starting multimodal pipeline", run_id)

        whisper_lang = os.environ.get("WHISPER_LANGUAGE", "en")
        asr = await asyncio.to_thread(transcribe_local_file, media_path, language=whisper_lang)

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
        cleanup_bundle(bundle)
