"""Unit tests for extraction metrics (thesis Section 5.2.1)."""

from __future__ import annotations

import pytest

from evaluation.extraction.metrics import (
    GoldName,
    PredName,
    category_accuracy,
    evaluate_video,
    geodesic_errors_km,
    haversine_km,
    levenshtein,
    match_names,
    mean,
    median,
    name_matches,
    normalize_name,
    stddev,
)


def test_levenshtein():
    assert levenshtein("", "") == 0
    assert levenshtein("abc", "") == 3
    assert levenshtein("", "abc") == 3
    assert levenshtein("kitten", "sitting") == 3
    assert levenshtein("flaw", "lawn") == 2


def test_normalize_name():
    assert normalize_name("Café de Flore") == "cafe de flore"
    assert normalize_name("  The   Louvre ") == "louvre"
    assert normalize_name("Tate  Modern") == "tate modern"


def test_name_matches_within_tolerance():
    # "eiffel towr" vs "eiffel tower": edit=1, max(11,12)=12, threshold=3.0 → match
    assert name_matches("The Louvre", "Louvre")
    assert name_matches("Eiffel Towr", "Eiffel Tower")


def test_name_matches_exceeds_tolerance():
    assert not name_matches("Eiffel Tower", "Notre Dame")


def test_name_matches_short_strings():
    # "cat" vs "car": edit=1, max=3, threshold=0.75 → 1 > 0.75 → no match
    assert not name_matches("cat", "car")
    assert name_matches("cat", "cat")


def test_name_matches_empty():
    # Both empty → True; one empty → edit=len(other), ratio=1.0 > 0.25 → False
    assert name_matches("", "")
    assert not name_matches("", "Louvre")
    assert not name_matches("Louvre", "")


def test_match_names_precision_recall_f1():
    preds = [PredName("A"), PredName("B"), PredName("Zzz")]
    golds = [GoldName("A"), GoldName("B"), GoldName("C")]
    m = match_names(preds, golds)
    assert m.tp == 2 and m.fp == 1 and m.fn == 1
    assert m.precision == pytest.approx(2 / 3)
    assert m.recall == pytest.approx(2 / 3)
    assert m.f1 == pytest.approx(2 / 3)


def test_match_names_empty_sets():
    # Empty predictions: no TPs, all gold is FN.
    m = match_names([], [GoldName("A")])
    assert m.tp == 0 and m.fn == 1
    assert m.precision == 0.0 and m.recall == 0.0

    # Empty gold: no TPs, all preds are FP.
    m2 = match_names([PredName("A")], [])
    assert m2.tp == 0 and m2.fp == 1
    assert m2.precision == 0.0 and m2.recall == 0.0


def test_match_names_partial_name_no_match():
    # "Louvre" has edit distance 7 from "Louvre Museum" (max=13, threshold=3.25)
    # so it does NOT match. The only TP is the exact "Louvre Museum" prediction.
    preds = [PredName("Louvre"), PredName("Louvre Museum")]
    golds = [GoldName("Louvre Museum")]
    m = match_names(preds, golds)
    assert m.tp == 1 and m.fp == 1 and m.fn == 0


def test_match_names_one_to_one_constraint():
    # "Eiffel Tower" (ratio=0) and "Effel Tower" (edit=1/12≈0.083) both match
    # gold "Eiffel Tower" within theta=0.25. The greedy pass commits the lower-
    # ratio match first; each gold can be used at most once, so the other pred
    # becomes FP.
    preds = [PredName("Eiffel Tower"), PredName("Effel Tower")]
    golds = [GoldName("Eiffel Tower")]
    m = match_names(preds, golds)
    assert m.tp == 1 and m.fp == 1 and m.fn == 0


def test_match_names_alternatives():
    preds = [PredName("Musée du Louvre")]
    golds = [GoldName("Louvre Museum", alternatives=["Musée du Louvre"])]
    m = match_names(preds, golds)
    assert m.tp == 1 and m.fp == 0 and m.fn == 0


def test_category_accuracy():
    # Correct match, wrong match, and unlabelled gold (excluded from denominator).
    # Comparison is case-insensitive.
    preds = [
        PredName("A", category="MUSEUM"),    # correct after casefold
        PredName("B", category="cafe"),      # wrong
        PredName("C", category="bar"),       # gold unlabelled → not counted
    ]
    golds = [
        GoldName("A", category="museum"),
        GoldName("B", category="restaurant"),
        GoldName("C", category=""),
    ]
    m = match_names(preds, golds)
    acc, correct, total = category_accuracy(preds, golds, m)
    assert total == 2 and correct == 1
    assert acc == pytest.approx(0.5)


def test_haversine_km():
    # Louvre to Eiffel Tower ≈ 3.1 km
    d = haversine_km(48.8606, 2.3376, 48.8584, 2.2945)
    assert 2.5 < d < 3.6


def test_geodesic_errors_km():
    # Pair contributes only when both sides have coordinates.
    preds = [
        PredName("Louvre", latitude=48.8606, longitude=2.3376),
        PredName("Flore"),  # no coords → pair skipped
    ]
    golds = [
        GoldName("Louvre", latitude=48.8610, longitude=2.3380),
        GoldName("Flore", latitude=48.8542, longitude=2.3324),
    ]
    m = match_names(preds, golds)
    errs = geodesic_errors_km(preds, golds, m)
    assert len(errs) == 1 and errs[0] < 0.1  # Louvre pair: ~tens of metres

    # Gold missing coords is also skipped.
    preds2 = [PredName("A", latitude=1.0, longitude=1.0)]
    golds2 = [GoldName("A")]
    m2 = match_names(preds2, golds2)
    assert geodesic_errors_km(preds2, golds2, m2) == []


def test_evaluate_video():
    preds = [PredName("Louvre", category="Museum", latitude=48.8606, longitude=2.3376)]
    golds = [GoldName("Louvre Museum", category="Museum", latitude=48.8606, longitude=2.3376,
                      alternatives=["Louvre"])]
    vm = evaluate_video("M1", "M", preds, golds)
    assert vm.tp == 1 and vm.precision == 1.0 and vm.recall == 1.0
    assert vm.category_accuracy == 1.0
    assert vm.mean_geodesic_km == pytest.approx(0.0, abs=1e-6)


def test_evaluate_video_no_coords():
    # When no TP pair has coordinates, geodesic properties are None.
    preds = [PredName("Louvre", category="Museum")]
    golds = [GoldName("Louvre", category="Museum")]
    vm = evaluate_video("A1", "A", preds, golds)
    assert vm.geodesic_errors_km == []
    assert vm.mean_geodesic_km is None
    assert vm.median_geodesic_km is None


def test_stats_helpers():
    assert mean([]) == 0.0 and mean([2, 4]) == 3.0
    assert stddev([5]) == 0.0 and stddev([2, 4]) == pytest.approx(1.0)
    assert median([]) == 0.0
    assert median([3, 1, 2]) == 2 and median([1, 2, 3, 4]) == 2.5
