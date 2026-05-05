"""
FR-01 / FR-04: Download short-form media and ingest caption/description metadata.

Tries merged video first (needed for OCR). Falls back to audio-only when video is unavailable.

YouTube/TikTok often return HTTP 403 on video fragments from cloud IPs; we retry with alternate
yt-dlp strategies (player clients, formats). Keep yt-dlp updated on deploy.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import tempfile
from dataclasses import dataclass
from typing import Any

import yt_dlp

logger = logging.getLogger(__name__)


@dataclass
class MediaBundle:
    """Paths are absolute; caller deletes temp_dir when done."""

    temp_dir: str
    title: str
    description: str
    video_path: str | None  # MP4/MKV/WebM etc., may be None if audio-only fallback
    audio_path: str | None  # Set when audio-only fallback


def _safe_stem(title: str, max_len: int = 80) -> str:
    stem = "".join(c if c.isalnum() or c in " -_" else "_" for c in title).strip("_")
    stem = stem[:max_len] if stem else "video"
    return stem or "video"


def _browser_like_headers() -> dict[str, str]:
    """Reduce bot-like requests (helps some CDNs; not a guarantee)."""
    return {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    }


def _extractor_args_from_env() -> dict[str, Any] | None:
    raw = (os.environ.get("YTDLP_EXTRACTOR_ARGS_JSON") or "").strip()
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        logger.warning("[ingest] Invalid YTDLP_EXTRACTOR_ARGS_JSON: %s", e)
        return None


def _base_ydl_opts() -> dict[str, Any]:
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "retries": 10,
        "fragment_retries": 10,
        "http_headers": _browser_like_headers(),
    }
    cookie = (os.environ.get("YTDLP_COOKIES_FILE") or "").strip()
    if cookie and os.path.isfile(cookie):
        opts["cookiefile"] = cookie
        logger.info("[ingest] Using cookie file for yt-dlp")
    ea = _extractor_args_from_env()
    if ea:
        opts["extractor_args"] = ea
    return opts


def _video_strategies() -> list[dict[str, Any]]:
    """
    Ordered fallbacks when the first format/client hits HTTP 403 on the video stream.
    Full env override replaces this list (one attempt) if YTDLP_EXTRACTOR_ARGS_JSON is set.
    """
    return [
        {
            "merge_output_format": "mp4",
            "format": "bv*+ba/bestvideo+bestaudio/b",
            "extractor_args": {
                "youtube": {"player_client": ["android", "web", "ios"]},
            },
        },
        {
            "merge_output_format": "mkv",
            "format": "bv*+ba/bestvideo+bestaudio/b",
            "extractor_args": {
                "youtube": {"player_client": ["tv_embedded", "android", "web"]},
            },
        },
        {
            "merge_output_format": "mp4",
            "format": "bestvideo+bestaudio/b",
            "extractor_args": {
                "youtube": {"player_client": ["ios", "web_creator", "web"]},
            },
        },
    ]


def _download_to_dir(url: str, opts: dict[str, Any]) -> None:
    yt_dlp.YoutubeDL(opts).download([url])


async def download_media_bundle(video_url: str) -> MediaBundle:
    """
    Download best-effort video file plus metadata from yt-dlp.
    Uses a dedicated temp directory; unlink paths after pipeline completes.
    """
    loop = asyncio.get_event_loop()
    temp_dir = tempfile.mkdtemp(prefix="easytravel_")

    base = _base_ydl_opts()
    ydl_info_opts = {**base, "quiet": True, "no_warnings": True}
    video_info = await loop.run_in_executor(
        None,
        lambda: yt_dlp.YoutubeDL(ydl_info_opts).extract_info(video_url, download=False),
    )
    title = video_info.get("title") or "video"
    description = video_info.get("description") or ""
    stem = _safe_stem(str(title))

    video_template = os.path.join(temp_dir, f"{stem}.%(ext)s")

    if base.get("extractor_args"):
        video_strategies_list: list[dict[str, Any]] = [
            {
                "merge_output_format": "mp4",
                "format": "bv*+ba/bestvideo+bestaudio/b",
            },
        ]
    else:
        video_strategies_list = _video_strategies()

    last_video_error: Exception | None = None
    for i, strat in enumerate(video_strategies_list):
        opts = {
            **base,
            **strat,
            "outtmpl": video_template,
            "overwrites": True,
        }
        try:
            await loop.run_in_executor(None, lambda o=opts: _download_to_dir(video_url, o))
            video_path = _find_media_file(temp_dir, extensions={".mp4", ".mkv", ".webm", ".mov"})
            if video_path:
                logger.info("[ingest] Video download OK (strategy %s)", i)
                return MediaBundle(
                    temp_dir=temp_dir,
                    title=str(title),
                    description=str(description),
                    video_path=video_path,
                    audio_path=None,
                )
            logger.warning("[ingest] yt-dlp exited cleanly but no video file found (strategy %s)", i)
        except Exception as e:
            last_video_error = e
            logger.warning("[ingest] Video download failed (strategy %s): %s", i, e)

    if last_video_error:
        logger.info("[ingest] All video strategies failed, trying audio-only: %s", last_video_error)

    audio_stem = os.path.join(temp_dir, stem)
    audio_opts = {
        **base,
        "format": "bestaudio/best",
        "postprocessors": [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"}
        ],
        "outtmpl": f"{audio_stem}.%(ext)s",
        "overwrites": True,
    }
    await loop.run_in_executor(
        None,
        lambda: _download_to_dir(video_url, audio_opts),
    )
    audio_path = _find_media_file(temp_dir, extensions={".mp3", ".m4a", ".opus", ".wav", ".webm"})
    if not audio_path:
        raise RuntimeError("Could not download video or audio for this URL.")

    return MediaBundle(
        temp_dir=temp_dir,
        title=str(title),
        description=str(description),
        video_path=None,
        audio_path=audio_path,
    )


def _find_media_file(directory: str, extensions: set[str]) -> str | None:
    best: tuple[float, str] | None = None
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext not in extensions:
            continue
        mtime = os.path.getmtime(path)
        cand = (mtime, path)
        if best is None or mtime > best[0]:
            best = cand
    return best[1] if best else None


def cleanup_bundle(bundle: MediaBundle) -> None:
    import shutil

    if os.path.isdir(bundle.temp_dir):
        shutil.rmtree(bundle.temp_dir, ignore_errors=True)
