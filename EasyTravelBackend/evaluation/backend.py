"""
Remote backend client for the evaluation harness.

Calls the *deployed* Modal backend over HTTP (the same endpoints the iOS app uses:
``POST /api/process-video`` and ``POST /api/plan-itinerary``) so the evaluation
exercises the production deployment end-to-end rather than re-running stages
locally. The base URL is taken from ``--backend-url`` or the ``EVAL_BACKEND_URL``
environment variable, e.g.

    https://YOUR-WORKSPACE--easytravel-api-serve.modal.run

Because the extraction call can run for several minutes (download + Whisper + OCR
+ LLM), the request timeout is generous, matching the iOS client.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any


class BackendError(RuntimeError):
    def __init__(self, status: int, detail: str | None):
        self.status = status
        self.detail = detail or ""
        super().__init__(f"backend {status}: {self.detail}")


@dataclass
class ProcessVideoResponse:
    status: int
    locations: list[dict[str, Any]] = field(default_factory=list)
    detail: str | None = None
    elapsed_seconds: float = 0.0


class RemoteBackend:
    """Thin HTTP client for the deployed EasyTravel backend."""

    # Pipeline can sit idle on the server for minutes (matches iOS BackendClient).
    PROCESS_TIMEOUT_S = 30 * 60
    PLAN_TIMEOUT_S = 120

    def __init__(self, base_url: str | None = None) -> None:
        base = (base_url or os.environ.get("EVAL_BACKEND_URL") or "").strip().rstrip("/")
        if not base:
            raise SystemExit(
                "No backend URL. Pass --backend-url or set EVAL_BACKEND_URL to the "
                "deployed Modal URL (e.g. https://...modal.run)."
            )
        self.base_url = base

    def process_video(self, video_url: str) -> ProcessVideoResponse:
        """POST /api/process-video. Returns the response even on HTTP error (status + detail)."""
        endpoint = f"{self.base_url}/api/process-video"
        body = json.dumps({"url": video_url}).encode("utf-8")
        req = urllib.request.Request(
            endpoint, data=body, method="POST",
            headers={"Content-Type": "application/json",
                     "User-Agent": "EasyTravelBackend-Eval/1.0"},
        )
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(req, timeout=self.PROCESS_TIMEOUT_S) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
                elapsed = time.perf_counter() - t0
                return ProcessVideoResponse(
                    status=resp.status,
                    locations=list(payload.get("locations", [])),
                    elapsed_seconds=elapsed,
                )
        except urllib.error.HTTPError as e:
            elapsed = time.perf_counter() - t0
            detail = _extract_detail(e)
            return ProcessVideoResponse(status=e.code, detail=detail, elapsed_seconds=elapsed)
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
            elapsed = time.perf_counter() - t0
            return ProcessVideoResponse(status=0, detail=str(e), elapsed_seconds=elapsed)

    def plan_itinerary(self, body: dict[str, Any]) -> tuple[dict[str, Any], float]:
        """POST /api/plan-itinerary (snake_case body). Returns (response_json, elapsed_seconds)."""
        endpoint = f"{self.base_url}/api/plan-itinerary"
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            endpoint, data=data, method="POST",
            headers={"Content-Type": "application/json",
                     "User-Agent": "EasyTravelBackend-Eval/1.0"},
        )
        t0 = time.perf_counter()

        def _do_request():
            try:
                with urllib.request.urlopen(req, timeout=self.PLAN_TIMEOUT_S) as resp:
                    return resp.status, resp.read()
            except urllib.error.HTTPError as e:
                return e.code, e.read()

        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(_do_request)
                status, raw = future.result(timeout=self.PLAN_TIMEOUT_S)
        except concurrent.futures.TimeoutError:
            raise BackendError(0, f"client-side timeout after {self.PLAN_TIMEOUT_S}s")

        elapsed = time.perf_counter() - t0
        if status >= 400:
            try:
                detail = json.loads(raw.decode("utf-8")).get("detail")
            except Exception:
                detail = None
            raise BackendError(status, detail)
        payload = json.loads(raw.decode("utf-8"))
        return payload, elapsed


def _extract_detail(e: urllib.error.HTTPError) -> str | None:
    try:
        return json.loads(e.read().decode("utf-8")).get("detail")
    except (json.JSONDecodeError, OSError, AttributeError):
        return None
