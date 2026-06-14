"""
Fetch and save the raw backend POI JSON for each fixture video.

Calls the deployed /api/process-video for every video in the manifest that has a
URL and writes the raw response (the POIs the backend extracted) to one JSON file
per video. No scoring, no gold list needed.

Usage:
    export EVAL_BACKEND_URL="https://...modal.run"
    python -m evaluation.extraction.fetch_responses                 # all videos
    python -m evaluation.extraction.fetch_responses --video A4 --video M1
    python -m evaluation.extraction.fetch_responses --retries 3
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import time

from .. import _paths  # noqa: F401
from ..backend import RemoteBackend
from .gold_schema import load_manifest, fixtures_dir

logger = logging.getLogger(__name__)


def default_out_dir() -> str:
    d = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "responses")
    os.makedirs(d, exist_ok=True)
    return d


def fetch_one(backend: RemoteBackend, entry, *, retries: int):
    """Call the backend, retrying transient failures (TikTok downloads are flaky)."""
    last = None
    for attempt in range(1, retries + 1):
        resp = backend.process_video(entry.url)
        last = resp
        if 200 <= resp.status < 300 and resp.locations:
            return resp
        logger.warning("[%s] attempt %d/%d → HTTP %s (%s)",
                       entry.video_id, attempt, retries, resp.status,
                       resp.detail or f"{len(resp.locations)} locations")
        if attempt < retries:
            time.sleep(3)
    return last


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ap = argparse.ArgumentParser(description="Save raw backend POI JSON per video.")
    ap.add_argument("--video", action="append", default=[],
                    help="Video id to fetch (repeatable). Default: all videos with a URL.")
    ap.add_argument("--backend-url", default=None, help="Deployed backend base URL (or EVAL_BACKEND_URL).")
    ap.add_argument("--manifest", default=None, help="Path to videos.json (default: bundled).")
    ap.add_argument("--out", default=None, help="Output directory (default: evaluation/responses).")
    ap.add_argument("--retries", type=int, default=2, help="Attempts per video on transient failure.")
    args = ap.parse_args()

    backend = RemoteBackend(args.backend_url)
    manifest = args.manifest or os.path.join(fixtures_dir(), "videos.json")
    entries = [e for e in load_manifest(manifest) if e.url]
    wanted = set(args.video)
    if wanted:
        entries = [e for e in entries if e.video_id in wanted]
    if not entries:
        raise SystemExit("No matching videos with a URL in the manifest.")

    out_dir = args.out or default_out_dir()
    logger.info("Backend → %s | saving to %s", backend.base_url, out_dir)

    summary = []
    for e in entries:
        logger.info("[%s] fetching %s", e.video_id, e.url)
        resp = fetch_one(backend, e, retries=args.retries)
        record = {
            "video_id": e.video_id,
            "group": e.group,
            "url": e.url,
            "http_status": resp.status,
            "elapsed_seconds": round(resp.elapsed_seconds, 2),
            "detail": resp.detail,
            "location_count": len(resp.locations),
            "locations": resp.locations,
        }
        path = os.path.join(out_dir, f"{e.video_id}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f, indent=2, ensure_ascii=False)
        ok = 200 <= resp.status < 300 and bool(resp.locations)
        logger.info("[%s] %s → %d POIs (%s)", e.video_id,
                    "OK" if ok else f"FAIL {resp.status}", len(resp.locations), path)
        summary.append((e.video_id, resp.status, len(resp.locations)))

    print("\n=== summary ===")
    for vid, status, n in summary:
        print(f"  {vid}: HTTP {status}, {n} POIs")
    print(f"\nSaved {len(summary)} file(s) to {out_dir}")


if __name__ == "__main__":
    main()
