"""
Gold-list schema and corpus manifest (thesis Section 5.2.1).

A *gold list* records, per video, the annotator's expected POIs: the canonical
name (as it would appear in a mapping service), inferred city, schema category,
optional valid alternatives (for ambiguous names), and optional ground-truth
coordinates for the geodesic-error metric.

Two file kinds:

* ``videos.json`` — corpus manifest: one entry per fixture video with id, group
  (A/O/M), source url, and the gold-list filename.
* ``gold/<id>.json`` — the gold list for one video.

Both are plain JSON so a non-programmer annotator can edit them directly.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any

from .metrics import GoldName

VALID_GROUPS = {"A", "O", "M"}

# Schema categories (Section 3.x consolidation prompt / Section 5.2.1).
SCHEMA_CATEGORIES = {
    "museum", "restaurant", "cafe", "landmark", "park", "hotel",
    "shopping", "nightlife", "neighborhood", "city", "other",
}


@dataclass
class GoldPOI:
    name: str
    category: str = ""
    city: str | None = None
    country: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    alternatives: list[str] = field(default_factory=list)

    def to_match_gold(self) -> GoldName:
        return GoldName(
            name=self.name,
            category=self.category,
            city=self.city,
            country=self.country,
            latitude=self.latitude,
            longitude=self.longitude,
            alternatives=list(self.alternatives),
        )


@dataclass
class GoldList:
    video_id: str
    group: str
    pois: list[GoldPOI]
    notes: str = ""

    def match_golds(self) -> list[GoldName]:
        return [p.to_match_gold() for p in self.pois]


@dataclass
class VideoEntry:
    video_id: str
    group: str
    url: str
    gold_file: str
    title: str = ""


# ---------------------------------------------------------------------------
# Loading + validation
# ---------------------------------------------------------------------------


class GoldDataError(ValueError):
    """Raised when a gold list or manifest is structurally invalid."""


def _require(cond: bool, msg: str) -> None:
    if not cond:
        raise GoldDataError(msg)


def load_gold_list(path: str) -> GoldList:
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    _require(isinstance(raw, dict), f"{path}: top level must be an object")
    video_id = str(raw.get("video_id") or "").strip()
    group = str(raw.get("group") or "").strip().upper()
    _require(bool(video_id), f"{path}: missing video_id")
    _require(group in VALID_GROUPS, f"{path}: group must be one of {sorted(VALID_GROUPS)}")
    pois_raw = raw.get("pois")
    _require(isinstance(pois_raw, list), f"{path}: 'pois' must be a list")

    pois: list[GoldPOI] = []
    for i, p in enumerate(pois_raw):
        _require(isinstance(p, dict), f"{path}: pois[{i}] must be an object")
        name = str(p.get("name") or "").strip()
        _require(bool(name), f"{path}: pois[{i}] missing name")
        category = str(p.get("category") or "").strip()
        if category and category.casefold() not in SCHEMA_CATEGORIES:
            # Warn-only: keep label so category accuracy still computes, but it is
            # off-schema and worth flagging to the annotator.
            pass
        lat = p.get("latitude")
        lon = p.get("longitude")
        pois.append(
            GoldPOI(
                name=name,
                category=category,
                city=(str(p["city"]).strip() if p.get("city") else None),
                country=(str(p["country"]).strip() if p.get("country") else None),
                latitude=(float(lat) if lat is not None else None),
                longitude=(float(lon) if lon is not None else None),
                alternatives=[str(a).strip() for a in (p.get("alternatives") or []) if str(a).strip()],
            )
        )
    return GoldList(video_id=video_id, group=group, pois=pois, notes=str(raw.get("notes") or ""))


def load_manifest(path: str) -> list[VideoEntry]:
    """Load ``videos.json`` corpus manifest."""
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    _require(isinstance(raw, dict) and isinstance(raw.get("videos"), list),
             f"{path}: expected object with a 'videos' array")
    entries: list[VideoEntry] = []
    seen: set[str] = set()
    for i, v in enumerate(raw["videos"]):
        _require(isinstance(v, dict), f"{path}: videos[{i}] must be an object")
        vid = str(v.get("id") or "").strip()
        group = str(v.get("group") or "").strip().upper()
        url = str(v.get("url") or "").strip()
        gold_file = str(v.get("gold_file") or f"gold/{vid}.json").strip()
        _require(bool(vid), f"{path}: videos[{i}] missing id")
        _require(vid not in seen, f"{path}: duplicate video id {vid!r}")
        _require(group in VALID_GROUPS, f"{path}: videos[{i}] group must be in {sorted(VALID_GROUPS)}")
        seen.add(vid)
        entries.append(VideoEntry(video_id=vid, group=group, url=url,
                                  gold_file=gold_file, title=str(v.get("title") or "")))
    return entries


def fixtures_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def load_corpus(
    manifest_path: str | None = None,
    *,
    require_all: bool = False,
    require_url: bool = True,
) -> tuple[list[VideoEntry], dict[str, GoldList]]:
    """
    Load the manifest and the referenced gold lists. Returns ``(entries, {id: GoldList})``
    where ``entries`` only contains videos that are *ready* (url present when
    ``require_url`` and a parseable gold list exists). Gold files are resolved
    relative to the manifest's directory.

    With ``require_all=True`` any missing/blank entry raises instead of being skipped,
    which is the right setting once the corpus is complete (e.g. CI gate).
    """
    manifest_path = manifest_path or os.path.join(fixtures_dir(), "videos.json")
    base = os.path.dirname(os.path.abspath(manifest_path))
    all_entries = load_manifest(manifest_path)
    ready: list[VideoEntry] = []
    golds: dict[str, GoldList] = {}
    for e in all_entries:
        if require_url and not e.url:
            _require(not require_all, f"{e.video_id}: missing url in manifest")
            continue
        gpath = e.gold_file if os.path.isabs(e.gold_file) else os.path.join(base, e.gold_file)
        if not os.path.isfile(gpath):
            _require(not require_all, f"{gpath}: gold list file not found for {e.video_id}")
            continue
        gl = load_gold_list(gpath)
        _require(gl.video_id == e.video_id,
                 f"{gpath}: video_id {gl.video_id!r} != manifest id {e.video_id!r}")
        if not gl.pois:
            _require(not require_all, f"{gpath}: gold list for {e.video_id} has no POIs")
            continue
        ready.append(e)
        golds[e.video_id] = gl
    return ready, golds
