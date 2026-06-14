"""Unit tests for anchor-city filter evaluation (thesis Sections 5.2.1, 3.6)."""

from __future__ import annotations

import pytest

from evaluation.extraction.anchor_filter_eval import (
    AnchorCase,
    AnchorConfusion,
    AnchorRow,
    default_fixture_path,
    evaluate_anchor_case,
    evaluate_anchor_cases,
    load_anchor_cases,
)


def _case(video_id, title, desc, rows):
    return AnchorCase(video_id=video_id, title=title, description=desc,
                      rows=[AnchorRow(*r) for r in rows])


def test_hyperlocal_single_city_strips_anchor():
    case = _case(
        "HL", "Things to do in London", "",
        [("London", "London", True),
         ("Tate Modern", "London", False),
         ("Borough Market", "London", False)],
    )
    conf = evaluate_anchor_case(case)
    assert conf.true_removed == 1 and conf.false_removed == 0 and conf.missed == 0
    assert conf.removal_precision == 1.0 and conf.recall == 1.0


def test_two_city_strips_only_anchor():
    # "Paris" is the metadata anchor; "Versailles" has a different name_key and is kept.
    case = _case(
        "TC", "Things to do in Paris", "plus a Versailles day trip",
        [("Paris", "Paris", True),
         ("Louvre Museum", "Paris", False),
         ("Versailles", "Versailles", False)],
    )
    conf = evaluate_anchor_case(case)
    assert conf.true_removed == 1 and conf.false_removed == 0 and conf.missed == 0


def test_regional_scope_strips_nothing():
    # "UK" in the title matches _REGION_SCOPE_RE → infer_anchor returns None;
    # no hub threshold met either → nothing stripped.
    case = _case(
        "RG", "UK road trip: cities to visit", "England itinerary",
        [("London", "London", False),
         ("Manchester", "Manchester", False),
         ("Edinburgh", "Edinburgh", False)],
    )
    conf = evaluate_anchor_case(case)
    assert conf.removed_total == 0


def test_majority_hub_strips_without_metadata():
    # No title/description; the majority-city column alone (100%, single city) fires.
    rows = [("Tokyo", "Tokyo", True)] + [
        (n, "Tokyo", False) for n in ("Shibuya", "Shinjuku", "Asakusa", "Ginza")
    ]
    conf = evaluate_anchor_case(_case("HUB", "", "", rows))
    assert conf.true_removed == 1 and conf.false_removed == 0


def test_multi_city_guard_prevents_hub_strip():
    # 3 distinct cities; Paris fraction = 12/14 ≈ 0.857 ≥ 0.85, so the hub path
    # adds "paris" to anchors_to_strip — but the ≥3-distinct-city guard (multi_city=True)
    # blocks the actual drop.
    rows = (
        [AnchorRow("Paris", "Paris", False)]
        + [AnchorRow(f"POI{i}", "Paris", False) for i in range(11)]
        + [AnchorRow("Versailles Palace", "Versailles", False)]
        + [AnchorRow("Rijksmuseum", "Amsterdam", False)]
    )
    conf = evaluate_anchor_case(AnchorCase(video_id="MC", title="", description="", rows=rows))
    assert conf.removed_total == 0 and conf.false_removed == 0


def test_strip_all_safeguard():
    # Single row: len(locations) ≤ 1 early-exits → anchor kept but "missed".
    conf = evaluate_anchor_case(_case("S1", "Things to do in Tokyo", "",
                                      [("Tokyo", "Tokyo", True)]))
    assert conf.true_removed == 0 and conf.missed == 1

    # Two identical anchor rows: stripping both would empty the list; safeguard
    # returns the original → both are missed.
    conf2 = evaluate_anchor_case(_case("S2", "Things to do in Tokyo", "",
                                       [("Tokyo", "Tokyo", True), ("Tokyo", "Tokyo", True)]))
    assert conf2.true_removed == 0 and conf2.missed == 2


def test_confusion_properties():
    conf = AnchorConfusion(true_removed=3, false_removed=1, missed=1, kept_correct=5)
    assert conf.a_pre == 4              # true_removed + missed
    assert conf.removed_total == 4     # true_removed + false_removed
    assert conf.removal_precision == pytest.approx(0.75)
    assert conf.recall == pytest.approx(0.75)
    assert conf.f1 == pytest.approx(2 * 0.75 * 0.75 / (0.75 + 0.75))


def test_aggregate_across_cases():
    cases = [
        _case("HL", "Things to do in London", "",
              [("London", "London", True), ("Tate Modern", "London", False)]),
        _case("RG", "UK road trip", "England",
              [("London", "London", False), ("Bath", "Bath", False)]),
    ]
    total, per_case = evaluate_anchor_cases(cases)
    assert total.true_removed == 1 and total.false_removed == 0
    assert len(per_case) == 2
    assert dict(per_case)["HL"].true_removed == 1
    assert dict(per_case)["RG"].true_removed == 0


def test_load_bundled_fixture():
    cases = load_anchor_cases(default_fixture_path())
    assert len(cases) == 3
    assert {c.video_id for c in cases} == {"HYPERLOCAL_1", "TWO_CITY_1", "REGIONAL_1"}

    total, _ = evaluate_anchor_cases(cases)
    assert total.false_removed == 0
    assert total.true_removed >= 2
