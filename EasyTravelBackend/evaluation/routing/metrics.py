"""
Routing metrics (thesis Section 5.2.2).

Pure functions over plan outputs:

* total travel time — sum of per-day provider travel seconds.
* optimality gap Δ = (T_heuristic − T*) / T* × 100 %.
* budget satisfaction — fraction of days whose total (travel + service) ≤ budget.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Sequence


@dataclass
class DayCost:
    day_index: int
    travel_seconds: float
    service_seconds: float
    within_budget: bool
    n_stops: int
    n_dropped: int

    @property
    def total_seconds(self) -> float:
        return self.travel_seconds + self.service_seconds


def total_travel_seconds(days: Sequence[DayCost]) -> float:
    return float(sum(d.travel_seconds for d in days))


def optimality_gap_percent(t_heuristic: float, t_optimal: float) -> float | None:
    """Δ as a percentage. None when the optimum is ~0 (degenerate, gap undefined)."""
    if t_optimal <= 1e-9:
        return None
    return (t_heuristic - t_optimal) / t_optimal * 100.0


def budget_satisfaction_rate(days: Sequence[DayCost]) -> float:
    """Fraction of days satisfying the declared budget (Section 5.2.2)."""
    if not days:
        return 1.0
    return sum(1 for d in days if d.within_budget) / len(days)


@dataclass
class InstanceResult:
    instance_id: str
    profile: str
    clustering: str
    days: list[DayCost] = field(default_factory=list)
    heuristic_travel_seconds: float = 0.0      # recomputed on the exact-comparison matrix
    optimal_travel_seconds: float = 0.0        # sum of per-day exact optima
    plan_total_travel_seconds: float = 0.0     # as reported by the planner
    per_day_gap_percent: list[float] = field(default_factory=list)
    planning_wall_seconds: float = 0.0
    exact_available: bool = True

    @property
    def instance_gap_percent(self) -> float | None:
        return optimality_gap_percent(self.heuristic_travel_seconds, self.optimal_travel_seconds)

    @property
    def budget_satisfaction(self) -> float:
        return budget_satisfaction_rate(self.days)


# --- aggregation ---------------------------------------------------------


def _mean(xs: Sequence[float]) -> float:
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else 0.0


def _mean_or_none(xs: Sequence[float | None]) -> float | None:
    """Mean of a sequence, returning None when no valid values exist."""
    valid = [x for x in xs if x is not None]
    return sum(valid) / len(valid) if valid else None


def _std(xs: Sequence[float]) -> float:
    xs = [x for x in xs if x is not None]
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs))


def _std_or_none(xs: Sequence[float | None]) -> float | None:
    """Std of a sequence, returning None when fewer than two valid values exist."""
    valid = [x for x in xs if x is not None]
    if len(valid) < 2:
        return None
    m = sum(valid) / len(valid)
    return math.sqrt(sum((x - m) ** 2 for x in valid) / len(valid))


@dataclass
class ProfileSummary:
    profile: str
    clustering: str
    n_instances: int
    travel_mean: float
    travel_std: float
    gap_mean: float | None       # None when no exact solution was available for any instance
    gap_std: float | None
    budget_satisfaction: float
    planning_wall_mean: float

    def as_dict(self) -> dict:
        return {
            "profile": self.profile,
            "clustering": self.clustering,
            "n_instances": self.n_instances,
            "total_travel_seconds": {"mean": self.travel_mean, "std": self.travel_std},
            "optimality_gap_percent": {"mean": self.gap_mean, "std": self.gap_std},
            "budget_satisfaction_rate": self.budget_satisfaction,
            "planning_wall_seconds_mean": self.planning_wall_mean,
        }


def summarize_profile(profile: str, clustering: str, results: Sequence[InstanceResult]) -> ProfileSummary:
    travel = [r.plan_total_travel_seconds for r in results]
    gaps: list[float | None] = [r.instance_gap_percent for r in results]
    all_days = [d for r in results for d in r.days]
    budget = budget_satisfaction_rate(all_days)
    return ProfileSummary(
        profile=profile,
        clustering=clustering,
        n_instances=len(results),
        travel_mean=_mean(travel),
        travel_std=_std(travel),
        gap_mean=_mean_or_none(gaps),
        gap_std=_std_or_none(gaps),
        budget_satisfaction=budget,
        planning_wall_mean=_mean([r.planning_wall_seconds for r in results]),
    )
