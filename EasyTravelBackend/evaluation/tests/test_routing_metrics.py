"""Unit tests for routing metrics + instance sampling (thesis Section 5.2.2)."""

from __future__ import annotations

import pytest

from evaluation.config import ROUTING_PROFILES
from evaluation.routing import metrics as rm
from evaluation.routing.instances import POI, POIDataset, build_instances


def _day(travel, service, within, n=3, dropped=0):
    return rm.DayCost(day_index=0, travel_seconds=travel, service_seconds=service,
                      within_budget=within, n_stops=n, n_dropped=dropped)


def test_day_cost_total_seconds():
    d = rm.DayCost(day_index=0, travel_seconds=3600.0, service_seconds=1800.0,
                   within_budget=True, n_stops=5, n_dropped=0)
    assert d.total_seconds == pytest.approx(5400.0)


def test_total_travel_seconds():
    assert rm.total_travel_seconds([_day(100, 50, True), _day(200, 60, True)]) == 300.0


def test_optimality_gap_percent():
    assert rm.optimality_gap_percent(110.0, 100.0) == pytest.approx(10.0)
    assert rm.optimality_gap_percent(100.0, 100.0) == pytest.approx(0.0)
    assert rm.optimality_gap_percent(100.0, 0.0) is None  # degenerate → undefined


def test_budget_satisfaction_rate():
    days = [_day(1, 1, True), _day(1, 1, False), _day(1, 1, True), _day(1, 1, True)]
    assert rm.budget_satisfaction_rate(days) == pytest.approx(0.75)
    assert rm.budget_satisfaction_rate([]) == 1.0


def test_instance_result_properties():
    r = rm.InstanceResult(
        instance_id="x", profile="p", clustering="k_means",
        days=[_day(1, 1, True), _day(1, 1, False)],
        heuristic_travel_seconds=120.0, optimal_travel_seconds=100.0,
    )
    assert r.instance_gap_percent == pytest.approx(20.0)
    assert r.budget_satisfaction == pytest.approx(0.5)


def test_summarize_profile():
    results = [
        rm.InstanceResult("a", "p", "k_means", days=[_day(1, 1, True)],
                          plan_total_travel_seconds=100.0,
                          heuristic_travel_seconds=110.0, optimal_travel_seconds=100.0),
        rm.InstanceResult("b", "p", "k_means", days=[_day(1, 1, True)],
                          plan_total_travel_seconds=200.0,
                          heuristic_travel_seconds=230.0, optimal_travel_seconds=200.0),
    ]
    s = rm.summarize_profile("p", "k_means", results)
    assert s.n_instances == 2
    assert s.travel_mean == pytest.approx(150.0)
    assert s.gap_mean == pytest.approx(12.5)   # (10% + 15%) / 2
    assert s.budget_satisfaction == 1.0


def test_summarize_profile_no_exact_solutions():
    # All instances have degenerate optimum (0) → all gaps are None;
    # gap_mean falls back to 0.0 (mean of an empty list).
    results = [rm.InstanceResult("a", "p", "k_means",
                                  days=[_day(1, 1, True)],
                                  plan_total_travel_seconds=100.0,
                                  heuristic_travel_seconds=100.0,
                                  optimal_travel_seconds=0.0)]
    s = rm.summarize_profile("p", "k_means", results)
    assert s.gap_mean == pytest.approx(0.0) and s.gap_std == pytest.approx(0.0)


def _dense_profile():
    return next(p for p in ROUTING_PROFILES if p.name == "dense_urban_core")


def test_build_instances_reproducible_and_sized():
    pool = [POI(f"p{i}", f"POI {i}", 48.85 + i * 1e-3, 2.35 + i * 1e-3, priority=3)
            for i in range(30)]
    ds = POIDataset(city="Paris", origin_lat=48.8566, origin_lon=2.3522, pois=pool)
    profile = _dense_profile()

    a = build_instances(profile, ds)
    b = build_instances(profile, ds)
    assert len(a) == profile.instances
    assert [[s.id for s in inst.stops] for inst in a] == \
           [[s.id for s in inst.stops] for inst in b]
    assert all(len(inst.stops) == min(profile.approx_stops, len(pool)) for inst in a)


def test_build_instances_all_distinct():
    # With 100 POIs and 5 draws of 20, all instances should be distinct.
    pool = [POI(f"p{i}", f"POI {i}", 48.85 + i * 1e-3, 2.35 + i * 1e-3) for i in range(100)]
    ds = POIDataset(city="Paris", origin_lat=48.85, origin_lon=2.35, pois=pool)
    insts = build_instances(_dense_profile(), ds)
    sampled = [tuple(sorted(s.id for s in inst.stops)) for inst in insts]
    assert len(set(sampled)) == _dense_profile().instances


def test_build_instances_small_pool():
    # When pool is smaller than approx_stops, all POIs are used in every instance.
    pool = [POI(f"p{i}", f"POI {i}", 48.85 + i * 1e-3, 2.35 + i * 1e-3) for i in range(5)]
    ds = POIDataset(city="Paris", origin_lat=48.85, origin_lon=2.35, pois=pool)
    insts = build_instances(_dense_profile(), ds)
    assert all(len(inst.stops) == len(pool) for inst in insts)
