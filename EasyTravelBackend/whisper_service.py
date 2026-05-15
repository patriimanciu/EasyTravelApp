"""
FR-02: ASR via local Whisper — transcript plus segment timestamps when available.

Works with any media path Whisper/ffmpeg can decode (video container or audio file).
"""

from __future__ import annotations

import asyncio
import os
from typing import Any

from media_ingest import MediaBundle, cleanup_bundle, download_media_bundle

# Whisper model name is part of run provenance (NFR-07)
WHISPER_MODEL_NAME = os.environ.get("WHISPER_MODEL", "base")


def empty_asr_result(*, note: str | None = None) -> dict[str, Any]:
    """Placeholder when ASR is skipped or fails (OCR/caption-only pipeline)."""
    return {
        "plain_text": "",
        "segments": [],
        "model_name": WHISPER_MODEL_NAME,
        "device": "skipped",
        "detected_language": None,
        "skipped_reason": note,
    }


def transcribe_local_file(
    media_path: str,
    *,
    language: str = "en",
) -> dict[str, Any]:
    """
    Run Whisper on a local file. Returns:
      - plain_text: str
      - segments: list[{start, end, text}]
      - model_name: str
      - device: str
    """
    import torch
    import whisper

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[asr] Using device: {device}, model: {WHISPER_MODEL_NAME}")
    model = whisper.load_model(WHISPER_MODEL_NAME, device=device)

    result = model.transcribe(
        media_path,
        language=language,
        fp16=device == "cuda",
        verbose=False,
    )

    segments_out: list[dict[str, Any]] = []
    for seg in result.get("segments") or []:
        segments_out.append(
            {
                "start": float(seg.get("start", 0.0)),
                "end": float(seg.get("end", 0.0)),
                "text": (seg.get("text") or "").strip(),
            }
        )

    plain = (result.get("text") or "").strip()
    return {
        "plain_text": plain,
        "segments": segments_out,
        "model_name": WHISPER_MODEL_NAME,
        "device": device,
        "detected_language": result.get("language"),
    }


def format_asr_block(asr: dict[str, Any]) -> str:
    """Human-readable ASR section for consolidation prompt."""
    if asr.get("skipped_reason") and not (asr.get("plain_text") or "").strip():
        return f"=== ASR TRANSCRIPT (FR-02) ===\n(Skipped: {asr['skipped_reason']})\n"
    lines = ["=== ASR TRANSCRIPT (FR-02) ==="]
    lines.append(f"Model: {asr.get('model_name')}  device: {asr.get('device')}")
    if asr.get("detected_language"):
        lines.append(f"Detected language: {asr['detected_language']}")
    lines.append("")
    for seg in asr.get("segments") or []:
        if not seg.get("text"):
            continue
        lines.append(f"[{seg['start']:.2f}s – {seg['end']:.2f}s] {seg['text']}")
    lines.append("")
    lines.append("Plain text:")
    lines.append(asr.get("plain_text") or "")
    return "\n".join(lines)


async def transcribe_video(video_url: str, language: str = "en", output_file: str | None = "output_data.txt"):
    """
    Legacy helper: download media + transcribe + optional save (same composite format as before).
    Prefer using media_ingest + transcribe_local_file from main pipeline for multimodal runs.
    """
    bundle = await download_media_bundle(video_url)
    try:
        path = bundle.asr_path()
        if not path:
            return None
        asr = transcribe_local_file(path, language=language)
        final_output = (
            f"--- VIDEO METADATA ---\n"
            f"Title: {bundle.title}\n"
            f"Caption/Description: {bundle.description}\n\n"
            f"--- TRANSCRIPT ---\n"
            f"{asr['plain_text']}\n"
        )
        if output_file:
            with open(output_file, "w", encoding="utf-8") as f:
                f.write(final_output)
            print(f"\nSuccess! Data saved to {output_file}")
        return final_output
    except Exception as e:
        print(f"Error: {e}")
        return None
    finally:
        cleanup_bundle(bundle)


async def main():
    url = input(
        "Whisper Video Transcription \n -------------------------- \n\n Please enter the video URL: \n"
    )
    await transcribe_video(url, output_file="trip_data.txt")


if __name__ == "__main__":
    asyncio.run(main())
