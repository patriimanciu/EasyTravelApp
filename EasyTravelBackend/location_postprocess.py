"""
Strip redundant anchor-city rows after LLM consolidation.

Models often still emit "London" as a POI when every row already uses city=London for hyperlocal
videos. Prompting alone is unreliable — we enforce scope rules here with lightweight heuristics.
"""

from __future__ import annotations

import logging
import re
from collections import Counter
from typing import Any, Sequence

logger = logging.getLogger(__name__)

# If metadata mentions these as *places*, do not treat a following capture as a single-city anchor.
_REGION_SCOPE_RE = re.compile(
    r"\b("
    r"uk|u\.?\s*k\.?|united\s+kingdom|great\s+britain|britain|england|scotland|wales"
    r"|northern\s+ireland|ireland\b|europe|eu\b|schengen"
    r"|usa|u\.?\s*s\.?\s*a\.?|united\s+states|canada"
    r"|california|florida|texas|new\s+york\s+state"
    r"|italy|france|spain|germany|greece|portugal|netherlands|belgium|switzerland|austria"
    r"|japan|china|thailand|vietnam|india|australia|mexico|brazil"
    r")\b",
    re.I,
)

_ANCHOR_FROM_METADATA_RES = (
    re.compile(
        r"(?:things\s+to\s+do|places\s+to\s+visit|places\s+to\s+(?:see|go)|spots\s+to\s+visit|top\s+(?:\d+\s+)?places)\s+in\s+(?:the\s+)?([A-Za-z][A-Za-z\s'\-\u2019]{1,42})",
        re.I,
    ),
    re.compile(
        r"(?:guide\s+to|weekend\s+in|(?:\d+\s+)?hours\s+in|day\s+in|days\s+in|trip\s+to|travel\s+to|visiting)\s+(?:the\s+)?([A-Za-z][A-Za-z\s'\-\u2019]{1,42})",
        re.I,
    ),
    re.compile(
        r"\bin\s+(?:the\s+)?(?:city\s+of\s+)?([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s*(?:\||[#•]|[\[\(]|travel|guide|tiktok|vlog|$)",
        re.I,
    ),
)


def normalize_place_key(name_or_city: str) -> str:
    """Lowercase single-token-ish key before comma (handles 'London, UK')."""
    t = name_or_city.strip().lower()
    t = re.sub(r"\s+", " ", t)
    t = t.split(",")[0].strip()
    return t


def _fragment_to_anchor(fragment: str) -> str | None:
    frag = fragment.strip()
    frag = re.split(r"[|•#\[\(\n]", frag)[0]
    frag = frag.strip(" \t-–—:|")
    frag = re.sub(r"\s+(travel|guide|vlog|tiktok|video|part\s*\d+)\s*$", "", frag, flags=re.I)
    words = frag.split()
    if len(words) > 4:
        frag = " ".join(words[:3])
    key = normalize_place_key(frag)
    if len(key) < 3:
        return None
    if _REGION_SCOPE_RE.search(frag):
        return None
    return key


def infer_anchor_from_metadata(title: str, description: str) -> str | None:
    """Guess hyperlocal anchor city from title/caption only when not obviously regional."""
    blob = f"{title or ''}\n{description or ''}"
    if _REGION_SCOPE_RE.search(blob):
        # Country/region-wide framing — avoid stripping legitimate city POIs using title alone.
        return None
    for rx in _ANCHOR_FROM_METADATA_RES:
        m = rx.search(blob)
        if not m:
            continue
        anchor = _fragment_to_anchor(m.group(1))
        if anchor:
            return anchor
    return None


def _distinct_city_keys(locations: Sequence[Any]) -> set[str]:
    keys: set[str] = set()
    for loc in locations:
        c = getattr(loc, "city", None)
        if c and str(c).strip():
            keys.add(normalize_place_key(str(c)))
    return keys


def _majority_hub(locations: Sequence[Any]) -> tuple[str | None, float]:
    keys = [
        normalize_place_key(str(loc.city))
        for loc in locations
        if getattr(loc, "city", None) and str(loc.city).strip()
    ]
    if not keys:
        return None, 0.0
    hub, n = Counter(keys).most_common(1)[0]
    frac = n / max(len(locations), 1)
    return hub, frac


def strip_redundant_anchor_city_rows(
    locations: list[Any],
    *,
    title: str,
    description: str,
) -> list[Any]:
    """
    Remove rows whose `name` equals the obvious scope anchor city when every other clue says
    hyperlocal single-city listing.

    Safe-guards:
    - If removing everything would occur, keep the original list.
    - If ≥3 distinct non-empty `city` values appear across rows, never strip (multi-city / regional).
    """
    if len(locations) <= 1:
        return locations

    distinct = _distinct_city_keys(locations)
    hub, frac = _majority_hub(locations)

    anchors_to_strip: set[str] = set()

    # Majority `city` column names one metro — tight thresholds so two-city videos aren't wrecked.
    if hub:
        if len(distinct) == 1 and frac >= 0.51:
            anchors_to_strip.add(hub)
        elif frac >= 0.85:
            anchors_to_strip.add(hub)

    # Metadata phrases ("things to do in London") when we're not in obvious regional scope.
    meta_anchor = infer_anchor_from_metadata(title, description)
    if meta_anchor:
        if len(distinct) <= 2:
            anchors_to_strip.add(meta_anchor)
        elif hub and normalize_place_key(meta_anchor) == hub and frac >= 0.45:
            anchors_to_strip.add(meta_anchor)

    if not anchors_to_strip:
        return locations

    kept: list[Any] = []
    dropped_names: list[str] = []

    # ≥3 different cities among rows → do not remove hub-named entries heuristically.
    multi_city = len(distinct) >= 3

    for loc in locations:
        name_key = normalize_place_key(str(loc.name))

        drop_row = False
        if name_key in anchors_to_strip and not multi_city:
            drop_row = True

        if drop_row:
            dropped_names.append(str(loc.name))
            continue
        kept.append(loc)

    if len(kept) == 0:
        logger.warning(
            "[postprocess] Anchor strip would remove all %d rows; skipping.",
            len(locations),
        )
        return locations

    if dropped_names:
        logger.info("[postprocess] Dropped redundant anchor rows: %s", dropped_names)

    return kept
