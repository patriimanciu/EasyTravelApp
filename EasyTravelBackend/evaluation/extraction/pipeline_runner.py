"""
Instrumented extraction pipeline (thesis Sections 5.2.2, 5.3.1).

Re-runs the exact stage functions used by ``main.py`` (download -> ASR -> OCR ->
consolidation -> anchor postprocess) with per-stage wall-clock timing and a
typed failure classification, so measured behaviour matches production while
exposing the latency decomposition and failure-class counts the chapter requires.

Network/model side effects live here; the metric modules stay pure.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .. import _paths  # noqa: F401  (puts backend modules on sys.path)
from ..config import ExtractionConfig
from ..latency import StageTimer

from consolidate import (
    CONSOLIDATION_SYSTEM_PROMPT,
    build_consolidation_user_message,
)
from location_postprocess import strip_redundant_anchor_city_rows
from media_ingest import cleanup_bundle, download_media_bundle
from ocr_service import extract_text_from_video
from whisper_service import empty_asr_result, format_asr_block, transcribe_local_file
from .metrics import PredName

logger = logging.getLogger(__name__)


class FailureClass(str, Enum):
    """Pipeline failure taxonomy (thesis Section 5.3.1)."""

    NONE = "none"
    DOWNLOAD_FAILURE = "download_failure"
    ASR_EMPTY = "asr_empty"
    OCR_EMPTY = "ocr_empty"
    LLM_REFUSAL = "llm_refusal"
    ALL_CHANNELS_EMPTY = "all_channels_empty_abort"
    ZERO_LOCATIONS = "zero_locations"  # parsed OK but no POIs after postprocess
    OTHER = "other"


@dataclass
class PipelineRun:
    """Result of one instrumented pipeline run for one (video, config) cell."""

    video_id: str
    config_label: str
    ok: bool
    failure: FailureClass
    predictions: list[PredName] = field(default_factory=list)
    latency: dict[str, Any] = field(default_factory=dict)
    n_before_postprocess: int = 0
    n_after_postprocess: int = 0
    asr_device: str | None = None
    asr_empty: bool = False
    ocr_empty: bool = False
    error_detail: str = ""


async def run_pipeline_once(
    video_id: str,
    url: str,
    config: ExtractionConfig,
    *,
    consolidation_model: str | None = None,
) -> PipelineRun:
    """
    Execute the full extraction pipeline once with timing. Applies the config's
    env overrides for the OCR sampling knobs read by the stage functions.
    ``WHISPER_MODEL`` is read at import time by ``whisper_service`` so it must be
    set in the environment *before* launching the process for it to take effect.
    """
    timer = StageTimer()
    # OCR knobs are read per-call from env (see main.py); apply them here.
    os.environ["OCR_SAMPLE_SECONDS"] = str(config.ocr_sample_seconds)
    os.environ["OCR_MAX_FRAMES"] = str(config.ocr_max_frames)
    model = consolidation_model or config.consolidation_model

    bundle = None
    try:
        # ---- download ----
        try:
            with timer.measure("download"):
                bundle = await download_media_bundle(url)
        except Exception as e:
            return PipelineRun(video_id, config.label, ok=False,
                               failure=FailureClass.DOWNLOAD_FAILURE,
                               latency=timer.as_dict(), error_detail=str(e))
        if bundle is None or (not bundle.video_path and not bundle.audio_path):
            return PipelineRun(video_id, config.label, ok=False,
                               failure=FailureClass.DOWNLOAD_FAILURE,
                               latency=timer.as_dict(),
                               error_detail="no downloadable media path")

        # ---- ASR ----
        whisper_lang = os.environ.get("WHISPER_LANGUAGE", "en")
        asr_path = bundle.asr_path()
        if asr_path:
            try:
                with timer.measure("asr"):
                    asr = transcribe_local_file(asr_path, language=whisper_lang)
            except Exception as e:
                logger.warning("[%s] ASR failed (graceful degrade): %s", video_id, e)
                asr = empty_asr_result(note=str(e))
        else:
            asr = empty_asr_result(note="no audio track")
        timer.asr_device = asr.get("device")
        transcript = (asr.get("plain_text") or "").strip()
        asr_empty = not transcript

        # ---- OCR ----
        ocr_strings: list[str] = []
        if bundle.video_path:
            try:
                ocr_lang = os.environ.get("OCR_TESS_LANG", "eng")
                with timer.measure("ocr"):
                    ocr_result = extract_text_from_video(
                        bundle.video_path,
                        sample_interval_seconds=config.ocr_sample_seconds,
                        max_frames=config.ocr_max_frames,
                        tesseract_lang=ocr_lang,
                    )
                ocr_strings = [x.text for x in ocr_result]
            except Exception as e:
                logger.warning("[%s] OCR failed (graceful degrade): %s", video_id, e)
        ocr_empty = not ocr_strings

        caption = (bundle.description or "").strip()
        if not transcript and not ocr_strings and not caption:
            return PipelineRun(video_id, config.label, ok=False,
                               failure=FailureClass.ALL_CHANNELS_EMPTY,
                               latency=timer.as_dict(), asr_device=timer.asr_device,
                               asr_empty=asr_empty, ocr_empty=ocr_empty,
                               error_detail="no usable text from ASR, OCR, or caption")

        # ---- consolidation (LLM) ----
        asr_block = format_asr_block(asr)
        user_content = build_consolidation_user_message(
            title=bundle.title, description=bundle.description,
            asr_block=asr_block, ocr_lines=ocr_strings,
        )
        try:
            with timer.measure("consolidation"):
                parsed = _consolidate_llm(user_content, model=model)
        except _LLMRefusal as e:
            return PipelineRun(video_id, config.label, ok=False,
                               failure=FailureClass.LLM_REFUSAL,
                               latency=timer.as_dict(), asr_device=timer.asr_device,
                               asr_empty=asr_empty, ocr_empty=ocr_empty,
                               error_detail=str(e))
        except Exception as e:
            return PipelineRun(video_id, config.label, ok=False,
                               failure=FailureClass.OTHER,
                               latency=timer.as_dict(), asr_device=timer.asr_device,
                               asr_empty=asr_empty, ocr_empty=ocr_empty,
                               error_detail=f"consolidation error: {e}")

        n_before = len(parsed)

        # ---- anchor-city postprocess ----
        with timer.measure("postprocess"):
            filtered = strip_redundant_anchor_city_rows(
                parsed, title=bundle.title, description=bundle.description
            )
        n_after = len(filtered)

        preds = [
            PredName(
                name=str(getattr(loc, "name", "")),
                category=str(getattr(loc, "category", "")),
                city=(str(getattr(loc, "city", "")) or None),
            )
            for loc in filtered
        ]

        failure = FailureClass.NONE if preds else FailureClass.ZERO_LOCATIONS
        return PipelineRun(
            video_id=video_id, config_label=config.label,
            ok=bool(preds), failure=failure, predictions=preds,
            latency=timer.as_dict(), n_before_postprocess=n_before,
            n_after_postprocess=n_after, asr_device=timer.asr_device,
            asr_empty=asr_empty, ocr_empty=ocr_empty,
        )
    finally:
        if bundle is not None:
            cleanup_bundle(bundle)


class _LLMRefusal(RuntimeError):
    pass


def _consolidate_llm(user_content: str, *, model: str) -> list[Any]:
    """
    Run the structured-output consolidation call (same as main.py) and return the
    parsed ``Location`` objects. Raises ``_LLMRefusal`` on an explicit refusal.
    """
    from openai import OpenAI
    # Import the response schema from the API module without starting FastAPI.
    from main import LocationExtraction

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    client = OpenAI(api_key=api_key)
    completion = client.beta.chat.completions.parse(
        model=model,
        messages=[
            {"role": "system", "content": CONSOLIDATION_SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ],
        response_format=LocationExtraction,
    )
    msg = completion.choices[0].message
    refusal = getattr(msg, "refusal", None)
    if refusal:
        raise _LLMRefusal(str(refusal))
    parsed = msg.parsed
    if parsed is None:
        raise RuntimeError("LLM returned no structured locations")
    return list(parsed.locations)
