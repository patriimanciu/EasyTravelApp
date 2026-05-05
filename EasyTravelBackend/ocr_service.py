"""
FR-03: Sample video frames at a configurable interval, OCR each frame (Tesseract),
deduplicate lines by normalized text equality (thesis Section 3 extraction).

NFR-02: OCR failures return empty lines without crashing the pipeline.
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class OCRLine:
    text: str
    frame_index: int
    timestamp_sec: float | None


def _normalize_for_dedupe(text: str) -> str:
    s = text.strip().lower()
    s = re.sub(r"\s+", " ", s)
    return s


def _resolve_tesseract_executable() -> str | None:
    """pytesseract does not search Homebrew paths unless PATH includes them."""
    explicit = (os.environ.get("TESSERACT_CMD") or "").strip()
    if explicit:
        return explicit if os.path.isfile(explicit) else shutil.which(explicit)
    return shutil.which("tesseract")


def _configure_pytesseract(pytesseract_mod) -> bool:
    exe = _resolve_tesseract_executable()
    if not exe:
        logger.warning(
            "[ocr] No tesseract binary found. Install tesseract (e.g. brew install tesseract) "
            "or set TESSERACT_CMD to the full path."
        )
        return False
    # Works across pytesseract versions
    inner = getattr(pytesseract_mod, "pytesseract", pytesseract_mod)
    inner.tesseract_cmd = exe
    logger.debug("[ocr] Using tesseract at %s", exe)
    return True


def extract_text_from_video(
    video_path: str,
    *,
    sample_interval_seconds: float = 2.0,
    max_frames: int = 45,
    tesseract_lang: str = "eng",
) -> list[OCRLine]:
    """
    Extract OCR lines from uniformly sampled frames using ffmpeg + Tesseract.

    sample_interval_seconds: average seconds between sampled frames (FR-03 configurable rate).
    """
    if sample_interval_seconds <= 0:
        sample_interval_seconds = 2.0

    lines: list[OCRLine] = []
    try:
        import pytesseract
        from PIL import Image
    except ImportError:
        logger.warning("[ocr] pytesseract/Pillow not installed; skipping OCR (NFR-02).")
        return lines

    if not _configure_pytesseract(pytesseract):
        return lines

    tess_config = os.environ.get("OCR_TESSERACT_CONFIG", "--oem 3 --psm 6")

    frames_dir = tempfile.mkdtemp(prefix="easytravel_frames_")
    try:
        fps_expr = f"fps=1/{sample_interval_seconds}"
        pattern = os.path.join(frames_dir, "frame_%05d.png")
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-nostdin",
            "-loglevel",
            "error",
            "-i",
            video_path,
            "-vf",
            f"{fps_expr},scale=1280:-1",
            "-frames:v",
            str(max_frames),
            "-y",
            "-f",
            "image2",
            pattern,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if proc.returncode != 0:
            logger.warning(
                "[ocr] ffmpeg frame extract failed (exit=%s): %s",
                proc.returncode,
                (proc.stderr or proc.stdout or "").strip() or "(no stderr)",
            )
            return lines

        pngs = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
        if not pngs:
            logger.warning(
                "[ocr] ffmpeg finished but wrote no PNGs (check codec/path): %s",
                video_path,
            )
            return lines

        logger.info("[ocr] Extracted %d frame(s) for Tesseract", len(pngs))

        seen_norm: set[str] = set()

        for idx, fname in enumerate(pngs):
            fpath = os.path.join(frames_dir, fname)
            try:
                img = Image.open(fpath).convert("RGB")
                raw = pytesseract.image_to_string(
                    img,
                    lang=tesseract_lang,
                    config=tess_config,
                )
            except Exception as e:
                if type(e).__name__ == "TesseractNotFoundError":
                    logger.warning("[ocr] Tesseract binary error: %s", e)
                    return lines
                logger.warning("[ocr] frame %s OCR failed: %s", fname, e)
                continue

            for raw_line in raw.splitlines():
                t = raw_line.strip()
                if len(t) < 2:
                    continue
                norm = _normalize_for_dedupe(t)
                if len(norm) < 2 or norm in seen_norm:
                    continue
                seen_norm.add(norm)
                ts = idx * sample_interval_seconds
                lines.append(OCRLine(text=t, frame_index=idx, timestamp_sec=ts))

        logger.info("[ocr] deduped lines kept: %d", len(lines))

    except FileNotFoundError:
        logger.warning("[ocr] ffmpeg not found on PATH; skipping OCR (NFR-02).")
    except subprocess.TimeoutExpired:
        logger.warning("[ocr] ffmpeg timed out; skipping OCR (NFR-02).")
    except subprocess.CalledProcessError as e:
        logger.warning("[ocr] ffmpeg extract failed: %s (NFR-02).", e)
    except Exception as e:
        logger.warning("[ocr] unexpected error: %s (NFR-02).", e)
    finally:
        shutil.rmtree(frames_dir, ignore_errors=True)

    return lines
