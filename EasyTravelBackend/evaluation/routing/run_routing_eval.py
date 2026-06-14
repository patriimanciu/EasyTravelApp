"""
Routing evaluation driver (thesis Sections 5.2.2, 5.3.2).

For each city profile (dense urban core, medium multi-day, large dispersed) it
draws five reproducible benchmark instances, runs the heuristic planner with the
fixed configuration (OSRM travel times, k-means clustering, priority rebalance,
seed 42), and reports total travel time, optimality gap against an exact TSP
solver, and budget-satisfaction rate. DBSCAN is reported separately for the dense
core profile to compare clustering strategies.

Usage:
    python -m evaluation.routing.run_routing_eval --profiles all
    python -m evaluation.routing.run_routing_eval --profiles dense_urban_core
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from typing import Any

from types import SimpleNamespace

from .. import _paths  # noqa: F401
from ..backend import RemoteBackend
from ..config import ROUTING_HEURISTIC, ROUTING_PROFILES, RoutingProfile, reports_dir
from ttdp_routing import StopSpec, planning_fields_from_visit_priority, plan_ttdp_itinerary
from . import metrics as rmetrics
from .exact_tsp import build_travel_matrix, exact_tour_cost
from .instances import Instance, build_instances, dataset_path_for, load_dataset

logger = logging.getLogger(__name__)


def _remote_plan_body(instance: Instance, specs: list[StopSpec], clustering_method: str) -> dict:
    """Build the snake_case /api/plan-itinerary request body for a benchmark instance."""
    return {
        "start_latitude": instance.origin_lat,
        "start_longitude": instance.origin_lon,
        "stops": [
            {
                "id": s.id,
                "latitude": s.lat,
                "longitude": s.lon,
                "visit_priority": s.priority,
                "service_time_seconds": s.service_seconds,
            }
            for s in specs
        ],
        "number_of_days": instance.days,
        "daily_budget_seconds": instance.daily_budget_seconds,
        "return_to_start": False,
        "travel_model": ROUTING_HEURISTIC["travel_model"],
        "clustering_seed": ROUTING_HEURISTIC["clustering_seed"],
        "clustering_method": clustering_method,
        "priority_rebalance": ROUTING_HEURISTIC["priority_rebalance"],
        "osrm_profile": ROUTING_HEURISTIC["osrm_profile"],
    }


def _days_from_remote(payload: dict) -> list[SimpleNamespace]:
    """Adapt /api/plan-itinerary response days to the local DayPlan attribute shape."""
    out: list[SimpleNamespace] = []
    for d in payload.get("days", []):
        out.append(
            SimpleNamespace(
                day_index=int(d.get("day_index", 0)),
                ordered_stop_ids=list(d.get("ordered_stop_ids", [])),
                total_travel_seconds=float(d.get("total_travel_seconds", 0.0)),
                total_service_seconds=float(d.get("total_service_seconds", 0.0)),
                within_budget=bool(d.get("within_budget", True)),
                dropped_stop_ids=list(d.get("dropped_stop_ids", [])),
            )
        )
    return out


def _stop_specs(instance: Instance) -> list[StopSpec]:
    specs: list[StopSpec] = []
    for s in instance.stops:
        weight, mandatory = planning_fields_from_visit_priority(s.priority)
        specs.append(
            StopSpec(
                id=s.id, lat=s.latitude, lon=s.longitude,
                weight=weight, mandatory=mandatory,
                service_seconds=s.service_time_seconds, priority=s.priority,
            )
        )
    return specs


def _evaluate_instance(
    instance: Instance,
    clustering_method: str,
    *,
    osrm_base_url: str | None,
    backend: RemoteBackend | None = None,
) -> rmetrics.InstanceResult:
    specs = _stop_specs(instance)
    coord_by_id = {s.id: (s.latitude, s.longitude) for s in instance.stops}

    if backend is not None:
        body = _remote_plan_body(instance, specs, clustering_method)
        payload, wall = backend.plan_itinerary(body)
        day_plans = _days_from_remote(payload)
    else:
        t0 = time.perf_counter()
        day_plans, _meta = plan_ttdp_itinerary(
            specs,
            instance.origin_lat,
            instance.origin_lon,
            number_of_days=instance.days,
            daily_budget_seconds=instance.daily_budget_seconds,
            return_to_start=False,
            travel_model=ROUTING_HEURISTIC["travel_model"],
            clustering_seed=ROUTING_HEURISTIC["clustering_seed"],
            clustering_method=clustering_method,
            priority_rebalance=ROUTING_HEURISTIC["priority_rebalance"],
            osrm_profile=ROUTING_HEURISTIC["osrm_profile"],
            osrm_base_url=osrm_base_url,
        )
        wall = time.perf_counter() - t0

    result = rmetrics.InstanceResult(
        instance_id=instance.instance_id,
        profile=instance.profile,
        clustering=clustering_method,
        planning_wall_seconds=wall,
    )

    ordered_days = sorted(day_plans, key=lambda d: d.day_index)
    prev_last: tuple[float, float] | None = None
    for dp in ordered_days:
        result.days.append(
            rmetrics.DayCost(
                day_index=dp.day_index,
                travel_seconds=dp.total_travel_seconds,
                service_seconds=dp.total_service_seconds,
                within_budget=dp.within_budget,
                n_stops=len(dp.ordered_stop_ids),
                n_dropped=len(dp.dropped_stop_ids),
            )
        )
        result.plan_total_travel_seconds += dp.total_travel_seconds

        # Exact comparison on the same matrix: [day_start] + ordered stops, open path.
        if not dp.ordered_stop_ids:
            prev_last = prev_last
            continue
        start = (instance.origin_lat, instance.origin_lon) if prev_last is None else prev_last
        coords = [start] + [coord_by_id[sid] for sid in dp.ordered_stop_ids]
        lats = [c[0] for c in coords]
        lons = [c[1] for c in coords]
        matrix, _used = build_travel_matrix(
            lats, lons,
            travel_model=ROUTING_HEURISTIC["travel_model"],
            average_speed_kmh=15.0,
            osrm_base_url=osrm_base_url,
            osrm_profile=ROUTING_HEURISTIC["osrm_profile"],
        )
        heur_cost = float(sum(matrix[i, i + 1] for i in range(len(coords) - 1)))
        _opt_order, opt_cost = exact_tour_cost(matrix, closed=False, start_index=0)
        result.heuristic_travel_seconds += heur_cost
        if opt_cost is not None:
            result.optimal_travel_seconds += opt_cost
            gap = rmetrics.optimality_gap_percent(heur_cost, opt_cost)
            if gap is not None:
                result.per_day_gap_percent.append(gap)
        else:
            result.exact_available = False
        prev_last = coord_by_id[dp.ordered_stop_ids[-1]]

    return result


def _run_profile(
    profile: RoutingProfile,
    *,
    dataset_override: dict[str, str] | None,
    osrm_base_url: str | None,
    backend: RemoteBackend | None = None,
) -> dict[str, Any]:
    ds_path = dataset_path_for(profile, dataset_override)
    if not os.path.isfile(ds_path):
        raise SystemExit(
            f"Dataset for profile '{profile.name}' not found at {ds_path}. "
            f"Run: python -m evaluation.routing.generate_datasets"
        )
    dataset = load_dataset(ds_path)
    if len(dataset.pois) < profile.approx_stops:
        logger.warning(
            "Dataset '%s' has %d POIs but profile '%s' wants ~%d; instances will use all POIs.",
            dataset.city, len(dataset.pois), profile.name, profile.approx_stops,
        )
    instances = build_instances(profile, dataset)

    methods = ["k_means"]
    if profile.compare_dbscan:
        methods.append("dbscan")

    block: dict[str, Any] = {"profile": profile.name, "city": dataset.city, "clustering": {}}
    for method in methods:
        results = [
            _evaluate_instance(inst, method, osrm_base_url=osrm_base_url, backend=backend)
            for inst in instances
        ]
        summary = rmetrics.summarize_profile(profile.name, method, results)
        block["clustering"][method] = {
            "summary": summary.as_dict(),
            "instances": [
                {
                    "instance_id": r.instance_id,
                    "n_days": len(r.days),
                    "plan_total_travel_seconds": r.plan_total_travel_seconds,
                    "heuristic_travel_seconds": r.heuristic_travel_seconds,
                    "optimal_travel_seconds": r.optimal_travel_seconds,
                    "instance_gap_percent": r.instance_gap_percent,
                    "exact_available": r.exact_available,
                    "budget_satisfaction": r.budget_satisfaction,
                    "planning_wall_seconds": r.planning_wall_seconds,
                }
                for r in results
            ],
        }
    return block


def _render_markdown(report: dict[str, Any]) -> str:
    lines = ["# Routing evaluation (thesis Chapter 5)", ""]
    lines.append("Heuristic: OSRM travel times, k-means clustering, priority rebalance, seed 42.")
    lines.append("")
    lines.append("| Profile | Clustering | n | Travel (s) mean±std | Opt. gap % mean±std | Budget sat. | Plan wall (s) |")
    lines.append("|---|---|---|---|---|---|---|")
    for prof in report.get("profiles", []):
        for method, blk in prof["clustering"].items():
            s = blk["summary"]
            tt = s["total_travel_seconds"]
            gp = s["optimality_gap_percent"]
            gp_mean = gp["mean"]
            gp_std = gp["std"]
            if gp_mean is None:
                gap_str = "N/A"
            else:
                std_part = f" ± {gp_std:.2f}" if gp_std is not None else ""
                gap_str = f"{gp_mean:.2f}{std_part}"
            lines.append(
                f"| {prof['profile']} ({prof['city']}) | {method} | {s['n_instances']} | "
                f"{tt['mean']:.0f} ± {tt['std']:.0f} | {gap_str} | "
                f"{s['budget_satisfaction_rate']*100:.1f}% | {s['planning_wall_seconds_mean']:.2f} |"
            )
    lines.append("")
    return "\n".join(lines)


def _write_reports(report: dict[str, Any]) -> tuple[str, str]:
    out_dir = reports_dir()
    ts = time.strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(out_dir, f"routing_eval_{ts}.json")
    md_path = os.path.join(out_dir, f"routing_eval_{ts}.md")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(_render_markdown(report))
    return json_path, md_path


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ap = argparse.ArgumentParser(description="Routing optimizer evaluation (thesis Chapter 5).")
    ap.add_argument("--profiles", default="all",
                    help="'all' or comma-separated profile names "
                         "(dense_urban_core,medium_multi_day,large_dispersed).")
    ap.add_argument("--osrm-base-url", default=os.environ.get("OSRM_BASE_URL"),
                    help="OSRM server base URL (defaults to env OSRM_BASE_URL or public server).")
    ap.add_argument("--backend-url", default=None,
                    help="Deployed backend base URL: call /api/plan-itinerary instead of "
                         "planning locally. Defaults to env EVAL_BACKEND_URL when --remote is set.")
    ap.add_argument("--remote", action="store_true",
                    help="Use the deployed Modal planner (requires --backend-url or EVAL_BACKEND_URL).")
    args = ap.parse_args()

    backend = None
    if args.remote or args.backend_url:
        backend = RemoteBackend(args.backend_url)
        logger.info("Routing via deployed backend → %s", backend.base_url)

    if args.profiles == "all":
        profiles = list(ROUTING_PROFILES)
    else:
        wanted = {p.strip() for p in args.profiles.split(",") if p.strip()}
        profiles = [p for p in ROUTING_PROFILES if p.name in wanted]
        if not profiles:
            raise SystemExit(f"No matching profiles for {args.profiles!r}")

    report: dict[str, Any] = {"heuristic": ROUTING_HEURISTIC, "profiles": []}
    for profile in profiles:
        logger.info("Evaluating profile %s", profile.name)
        report["profiles"].append(
            _run_profile(profile, dataset_override=None,
                         osrm_base_url=args.osrm_base_url, backend=backend)
        )

    json_path, md_path = _write_reports(report)
    print(f"Routing report written:\n  {json_path}\n  {md_path}")


if __name__ == "__main__":
    main()
