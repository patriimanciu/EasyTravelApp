"""Unit tests for the gold-list schema + corpus loader (thesis Section 5.2.1).

These tests build their own fixtures in tmp dirs so they do not depend on the
editable corpus under fixtures/ (which the annotator fills in).
"""

from __future__ import annotations

import json
import os

import pytest

from evaluation.extraction import gold_schema as gs


def _write(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f)
    return str(path)


# ---------------------------------------------------------------------------
# load_gold_list
# ---------------------------------------------------------------------------

def test_load_and_validate_gold(tmp_path):
    p = _write(tmp_path / "g.json", {
        "video_id": "M1", "group": "M",
        "pois": [
            {"name": "Louvre Museum", "category": "Museum", "city": "Paris",
             "country": "France", "latitude": 48.86, "longitude": 2.33,
             "alternatives": ["Musée du Louvre"]},
        ],
    })
    gl = gs.load_gold_list(p)
    assert gl.video_id == "M1" and gl.group == "M"
    assert gl.pois[0].name == "Louvre Museum"
    assert "Musée du Louvre" in gl.match_golds()[0].alternatives


def test_invalid_group_rejected(tmp_path):
    p = _write(tmp_path / "bad.json", {"video_id": "X1", "group": "Z", "pois": []})
    with pytest.raises(gs.GoldDataError):
        gs.load_gold_list(p)


def test_missing_name_rejected(tmp_path):
    p = _write(tmp_path / "bad.json",
               {"video_id": "X1", "group": "A", "pois": [{"category": "Museum"}]})
    with pytest.raises(gs.GoldDataError):
        gs.load_gold_list(p)


def test_match_golds_conversion(tmp_path):
    # GoldList.match_golds() must faithfully copy all fields to GoldName objects.
    p = _write(tmp_path / "g.json", {
        "video_id": "A1", "group": "A",
        "pois": [
            {"name": "Eiffel Tower", "category": "landmark", "city": "Paris",
             "country": "France", "latitude": 48.8584, "longitude": 2.2945,
             "alternatives": ["Tour Eiffel", "La Tour Eiffel"]},
        ],
    })
    gl = gs.load_gold_list(p)
    golds = gl.match_golds()
    assert len(golds) == 1
    g = golds[0]
    assert g.name == "Eiffel Tower"
    assert g.category == "landmark"
    assert g.city == "Paris"
    assert g.country == "France"
    assert g.latitude == pytest.approx(48.8584)
    assert g.longitude == pytest.approx(2.2945)
    assert "Tour Eiffel" in g.alternatives
    assert "La Tour Eiffel" in g.alternatives


# ---------------------------------------------------------------------------
# load_manifest
# ---------------------------------------------------------------------------

def test_manifest_duplicate_id_rejected(tmp_path):
    p = _write(tmp_path / "videos.json", {"videos": [
        {"id": "A1", "group": "A", "url": "u", "gold_file": "g.json"},
        {"id": "A1", "group": "A", "url": "u", "gold_file": "g.json"},
    ]})
    with pytest.raises(gs.GoldDataError):
        gs.load_manifest(p)


# ---------------------------------------------------------------------------
# load_corpus
# ---------------------------------------------------------------------------

def test_load_corpus_skips_unready_entries(tmp_path):
    # A2 has a gold list with POIs and a url → ready. A1 has a blank url → skipped.
    _write(tmp_path / "a2.json", {"video_id": "A2", "group": "A",
                                  "pois": [{"name": "Borough Market", "category": "Shopping"}]})
    manifest = _write(tmp_path / "videos.json", {"videos": [
        {"id": "A1", "group": "A", "url": "", "gold_file": "a2.json"},
        {"id": "A2", "group": "A", "url": "https://x", "gold_file": "a2.json"},
    ]})
    entries, golds = gs.load_corpus(manifest, require_url=True)
    assert [e.video_id for e in entries] == ["A2"]
    assert golds["A2"].pois


def test_load_corpus_empty_pois_skipped(tmp_path):
    _write(tmp_path / "a1.json", {"video_id": "A1", "group": "A", "pois": []})
    manifest = _write(tmp_path / "videos.json", {"videos": [
        {"id": "A1", "group": "A", "url": "https://x", "gold_file": "a1.json"},
    ]})
    entries, golds = gs.load_corpus(manifest, require_url=True)
    assert entries == [] and golds == {}


def test_load_corpus_require_all_raises_on_missing_gold(tmp_path):
    # require_all=True should raise GoldDataError when a gold file is absent.
    manifest = _write(tmp_path / "videos.json", {"videos": [
        {"id": "A1", "group": "A", "url": "https://x", "gold_file": "nonexistent.json"},
    ]})
    with pytest.raises(gs.GoldDataError):
        gs.load_corpus(manifest, require_all=True)


# ---------------------------------------------------------------------------
# Bundled corpus
# ---------------------------------------------------------------------------

def test_bundled_manifest_parses():
    """The shipped corpus manifest must stay structurally valid (15 video slots)."""
    manifest = os.path.join(gs.fixtures_dir(), "videos.json")
    entries = gs.load_manifest(manifest)
    assert len(entries) == 15
    assert sum(1 for e in entries if e.group == "A") == 5
    assert sum(1 for e in entries if e.group == "O") == 5
    assert sum(1 for e in entries if e.group == "M") == 5
