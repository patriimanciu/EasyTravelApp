"""
Reference geocoder for the geodesic-error metric (Section 5.2.1).

The backend pipeline returns POI *names* (coordinate resolution happens on-device
via MapKit, Section 3.5). To compute geodesic error server-side, both the gold
canonical name and the predicted name are resolved through a single reference
geocoder so the comparison is device-independent (addressing the reproducibility
limitation in Section 3.7).

Default backend: OpenStreetMap Nominatim (same data family as the public OSRM
server). Results are cached on disk so repeated evaluation runs are deterministic
and do not hammer the public endpoint. Respect the Nominatim usage policy
(max 1 req/s, descriptive User-Agent) when geocoding fresh names.
"""

from __future__ import annotations

import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

logger = logging.getLogger(__name__)

DEFAULT_NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
DEFAULT_USER_AGENT = "EasyTravelBackend-Eval/1.0 (thesis evaluation harness)"


@dataclass(frozen=True)
class GeocodeResult:
    latitude: float
    longitude: float
    display_name: str


def _cache_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.environ.get("EVAL_GEOCODE_CACHE") or os.path.join(here, ".geocode_cache.json")


class Geocoder:
    """Disk-cached Nominatim geocoder. Returns ``None`` when nothing resolves."""

    def __init__(
        self,
        base_url: str | None = None,
        *,
        user_agent: str | None = None,
        min_interval_s: float = 1.05,
        timeout_s: float = 20.0,
    ) -> None:
        self.base_url = (base_url or os.environ.get("NOMINATIM_URL") or DEFAULT_NOMINATIM_URL).rstrip("/")
        self.user_agent = user_agent or os.environ.get("NOMINATIM_USER_AGENT") or DEFAULT_USER_AGENT
        self.min_interval_s = float(min_interval_s)
        self.timeout_s = float(timeout_s)
        self._last_request_t = 0.0
        self._cache: dict[str, dict | None] = {}
        self._load_cache()

    def _load_cache(self) -> None:
        path = _cache_path()
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    self._cache = json.load(f)
            except (OSError, json.JSONDecodeError):
                self._cache = {}

    def _save_cache(self) -> None:
        try:
            with open(_cache_path(), "w", encoding="utf-8") as f:
                json.dump(self._cache, f, indent=2, sort_keys=True)
        except OSError as e:
            logger.warning("[geocode] cache save failed: %s", e)

    @staticmethod
    def _key(name: str, city: str | None, country: str | None) -> str:
        return "|".join([(name or "").strip().lower(),
                         (city or "").strip().lower(),
                         (country or "").strip().lower()])

    def geocode(
        self,
        name: str,
        *,
        city: str | None = None,
        country: str | None = None,
    ) -> GeocodeResult | None:
        key = self._key(name, city, country)
        if key in self._cache:
            cached = self._cache[key]
            if cached is None:
                return None
            return GeocodeResult(cached["lat"], cached["lon"], cached.get("display_name", ""))

        query = ", ".join(p for p in [name, city, country] if p and p.strip())
        result = self._request(query)
        self._cache[key] = (
            None if result is None
            else {"lat": result.latitude, "lon": result.longitude, "display_name": result.display_name}
        )
        self._save_cache()
        return result

    def _request(self, query: str) -> GeocodeResult | None:
        # Throttle to respect Nominatim's usage policy.
        wait = self.min_interval_s - (time.monotonic() - self._last_request_t)
        if wait > 0:
            time.sleep(wait)
        params = urllib.parse.urlencode({"q": query, "format": "jsonv2", "limit": 1})
        url = f"{self.base_url}?{params}"
        req = urllib.request.Request(url, headers={"User-Agent": self.user_agent})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
            logger.warning("[geocode] request failed for %r: %s", query, e)
            return None
        finally:
            self._last_request_t = time.monotonic()
        if not payload:
            return None
        top = payload[0]
        try:
            return GeocodeResult(float(top["lat"]), float(top["lon"]), str(top.get("display_name", "")))
        except (KeyError, TypeError, ValueError):
            return None
