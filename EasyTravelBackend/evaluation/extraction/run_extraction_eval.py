"""
Extraction evaluation driver (thesis Sections 5.2.1, 5.3.1).

Processes each fixture video under each configuration, ``RUNS_PER_CELL`` times,
and reports per-group precision/recall/F1, category accuracy, geodesic-error
distributions, anchor-filter performance, pipeline-latency decomposition, and
failure-class counts. Means and standard deviations across runs surface LLM
non-determinism.

Usage:
    python -m evaluation.extraction.run_extraction_eval \
        --manifest evaluation/extraction/fixtures/videos.json \
        --configs single-axis \
        --runs 3 \
        --geocode

Requires the runtime stack (yt-dlp, ffmpeg, whisper, tesseract) and
OPENAI_API_KEY for the consolidation stage. Without ``--geocode`` the
geodesic-error metric is skipped.
"""

from __future__ import annotations

import argparse
import asyncio
import concurrent.futures
import json
import logging
import os
import time
from dataclasses import asdict
from typing import Any

from .. import _paths  # noqa: F401
from ..backend import ProcessVideoResponse, RemoteBackend
from ..config import (
    BASELINE,
    GROUP_LABELS,
    NAME_MATCH_THETA,
    RUNS_PER_CELL,
    ExtractionConfig,
    full_matrix_configs,
    reports_dir,
    single_axis_configs,
)
from ..geocode import Geocoder
from . import anchor_filter_eval
from .gold_schema import GoldList, load_corpus
from .metrics import (
    GoldName,
    PredName,
    evaluate_video,
    match_names,
    mean,
    median,
    stddev,
)
from .pipeline_runner import FailureClass, PipelineRun, run_pipeline_once

logger = logging.getLogger(__name__)


def _select_configs(name: str) -> list[ExtractionConfig]:
    if name == "baseline":
        return [BASELINE]
    if name == "single-axis":
        return single_axis_configs()
    if name == "full-matrix":
        return full_matrix_configs()
    raise SystemExit(f"unknown --configs {name!r} (use baseline|single-axis|full-matrix)")


def _summary(values: list[float]) -> dict[str, float | int]:
    return {
        "mean": mean(values),
        "std": stddev(values),
        "min": min(values) if values else 0.0,
        "max": max(values) if values else 0.0,
        "n": len(values),
    }


def _poi_dict(name: str, category: str, city: str | None) -> dict:
    return {"name": name, "category": category, "city": city}


def _build_comparison(
    runs: list[PipelineRun],
    gold_names: list[GoldName],
    theta: float,
) -> list[dict]:
    """Per-run match table: which predictions were TP/FP and which golds were FN."""
    result = []
    for run in runs:
        if not run.ok:
            result.append({"ok": False, "failure": run.failure.value})
            continue
        m = match_names(run.predictions, gold_names, theta=theta)
        result.append({
            "ok": True,
            "tp": [{"pred": run.predictions[pi].name, "gold": gold_names[gi].name}
                   for pi, gi in m.matched_pairs],
            "fp": [run.predictions[pi].name for pi in m.false_positive_pred_indices],
            "fn": [gold_names[gi].name for gi in m.false_negative_gold_indices],
        })
    return result


async def _run_cells(
    entries,
    configs: list[ExtractionConfig],
    runs: int,
) -> list[PipelineRun]:
    """Local instrumented mode: execute every (config, video, run) cell and collect raw runs."""
    all_runs: list[PipelineRun] = []
    for config in configs:
        for e in entries:
            for r in range(runs):
                logger.info("config=%s video=%s run=%d/%d", config.label, e.video_id, r + 1, runs)
                run = await run_pipeline_once(e.video_id, e.url, config)
                all_runs.append(run)
    return all_runs


def _classify_remote(resp: ProcessVideoResponse) -> tuple[bool, FailureClass]:
    """Map a deployed /api/process-video response to a typed failure class (Section 5.3.1)."""
    detail = (resp.detail or "").lower()
    if resp.status == 0:
        return False, FailureClass.DOWNLOAD_FAILURE  # network/transport-level
    if 200 <= resp.status < 300:
        if not resp.locations:
            return False, FailureClass.ZERO_LOCATIONS
        return True, FailureClass.NONE
    if "download" in detail or "no downloadable media" in detail:
        return False, FailureClass.DOWNLOAD_FAILURE
    if "no usable text" in detail:
        return False, FailureClass.ALL_CHANNELS_EMPTY
    if "refusal" in detail:
        return False, FailureClass.LLM_REFUSAL
    return False, FailureClass.OTHER


def _remote_to_run(video_id: str, config_label: str, resp: ProcessVideoResponse) -> PipelineRun:
    ok, failure = _classify_remote(resp)
    preds = [
        PredName(
            name=str(loc.get("name", "")),
            category=str(loc.get("category", "")),
            city=(str(loc.get("city")) if loc.get("city") else None),
        )
        for loc in resp.locations
    ]
    return PipelineRun(
        video_id=video_id,
        config_label=config_label,
        ok=ok,
        failure=failure,
        predictions=preds,
        latency={"total": resp.elapsed_seconds, "asr_device": "remote"},
        n_before_postprocess=0,
        n_after_postprocess=len(preds),
        asr_device="remote",
        error_detail=resp.detail or "",
    )


def _run_cells_remote(
    entries,
    backend: RemoteBackend,
    runs: int,
    config_label: str,
    per_video_timeout: int = 600,
) -> list[PipelineRun]:
    """Remote mode: call the deployed Modal /api/process-video for each (video, run)."""
    n_total = len(entries) * runs
    n_done = 0
    all_runs: list[PipelineRun] = []
    for e in entries:
        for r in range(runs):
            n_done += 1
            print(f"[{n_done}/{n_total}] {e.video_id} run {r + 1}/{runs} …", flush=True)
            t0 = time.perf_counter()
            try:
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    future = pool.submit(backend.process_video, e.url)
                    resp = future.result(timeout=per_video_timeout)
            except concurrent.futures.TimeoutError:
                elapsed = time.perf_counter() - t0
                print(f"  ✗ timed out after {elapsed:.0f}s — skipping", flush=True)
                logger.warning("[remote] %s run %d timed out after %.0fs",
                               e.video_id, r + 1, elapsed)
                all_runs.append(PipelineRun(
                    video_id=e.video_id, config_label=config_label,
                    ok=False, failure=FailureClass.OTHER,
                    error_detail=f"client-side timeout after {per_video_timeout}s",
                ))
                continue
            elapsed = time.perf_counter() - t0
            run = _remote_to_run(e.video_id, config_label, resp)
            status = "✓" if run.ok else "✗"
            detail = f" ({run.failure.value}: {run.error_detail})" if not run.ok else ""
            print(f"  {status} {elapsed:.1f}s{detail}", flush=True)
            if not run.ok:
                logger.warning("[remote] %s run %d failed: %s (%s)",
                               e.video_id, r + 1, run.failure.value, run.error_detail)
            all_runs.append(run)
    return all_runs


def _geocode_predictions(
    runs: list[PipelineRun],
    golds: dict[str, GoldList],
) -> None:
    """
    Resolve predicted names to coordinates (in place) so the geodesic-error metric
    can compare against gold coordinates. Uses the gold list's majority city/country
    as a disambiguation hint. Cached on disk.
    """
    geocoder = Geocoder()
    for run in runs:
        gl = golds.get(run.video_id)
        hint_city = None
        hint_country = None
        if gl and gl.pois:
            hint_city = next((p.city for p in gl.pois if p.city), None)
            hint_country = next((p.country for p in gl.pois if p.country), None)
        for pred in run.predictions:
            res = geocoder.geocode(pred.name, city=pred.city or hint_city, country=hint_country)
            if res is not None:
                pred.latitude = res.latitude
                pred.longitude = res.longitude


def _aggregate(
    runs: list[PipelineRun],
    entries,
    configs: list[ExtractionConfig],
    golds: dict[str, GoldList],
    theta: float,
) -> dict[str, Any]:
    by_video = {e.video_id: e for e in entries}
    # index runs by (config_label, video_id)
    cells: dict[tuple[str, str], list[PipelineRun]] = {}
    for run in runs:
        cells.setdefault((run.config_label, run.video_id), []).append(run)

    report: dict[str, Any] = {"theta": theta, "configs": {}}
    for config in configs:
        cfg_block: dict[str, Any] = {"config": config.as_dict(), "videos": {}, "groups": {}, "failures": {}}
        group_acc: dict[str, dict[str, list[float]]] = {}
        failure_counts: dict[str, int] = {}
        latency_stage_vals: dict[str, list[float]] = {}
        latency_by_device: dict[str, list[float]] = {}

        for e in entries:
            cell_runs = cells.get((config.label, e.video_id), [])
            gl = golds.get(e.video_id)
            if gl is None:
                continue
            match_golds = gl.match_golds()

            run_metrics = []
            for run in cell_runs:
                failure_counts[run.failure.value] = failure_counts.get(run.failure.value, 0) + 1
                # latency decomposition (successful or not, count what ran)
                for stage, val in (run.latency or {}).items():
                    if stage in ("total", "asr_device"):
                        continue
                    if isinstance(val, (int, float)):
                        latency_stage_vals.setdefault(stage, []).append(float(val))
                if isinstance(run.latency.get("total"), (int, float)):
                    dev = run.asr_device or "unknown"
                    latency_by_device.setdefault(dev, []).append(float(run.latency["total"]))
                if not run.ok:
                    continue
                m = evaluate_video(e.video_id, e.group, run.predictions, match_golds, theta=theta)
                run_metrics.append(m)

            video_block = {
                "group": e.group,
                "n_runs": len(cell_runs),
                "n_ok": len(run_metrics),
                "precision": _summary([m.precision for m in run_metrics]),
                "recall": _summary([m.recall for m in run_metrics]),
                "f1": _summary([m.f1 for m in run_metrics]),
                "category_accuracy": _summary([m.category_accuracy for m in run_metrics]),
                "geodesic_km_mean": _summary(
                    [m.mean_geodesic_km for m in run_metrics if m.mean_geodesic_km is not None]
                ),
                "gold": [_poi_dict(p.name, p.category, p.city) for p in gl.pois],
                "comparison": _build_comparison(cell_runs, gl.match_golds(), theta),
            }
            cfg_block["videos"][e.video_id] = video_block

            if run_metrics:
                g = group_acc.setdefault(e.group, {"precision": [], "recall": [], "f1": [], "category_accuracy": [], "geodesic_km": []})
                g["precision"].append(mean([m.precision for m in run_metrics]))
                g["recall"].append(mean([m.recall for m in run_metrics]))
                g["f1"].append(mean([m.f1 for m in run_metrics]))
                g["category_accuracy"].append(mean([m.category_accuracy for m in run_metrics]))
                geo = [k for m in run_metrics for k in m.geodesic_errors_km]
                g["geodesic_km"].extend(geo)

        for group, vals in group_acc.items():
            cfg_block["groups"][group] = {
                "label": GROUP_LABELS.get(group, group),
                "precision": _summary(vals["precision"]),
                "recall": _summary(vals["recall"]),
                "f1": _summary(vals["f1"]),
                "category_accuracy": _summary(vals["category_accuracy"]),
                "geodesic_km": {
                    "mean": mean(vals["geodesic_km"]) if vals["geodesic_km"] else None,
                    "median": median(vals["geodesic_km"]) if vals["geodesic_km"] else None,
                    "n": len(vals["geodesic_km"]),
                },
            }

        cfg_block["failures"] = failure_counts
        cfg_block["latency_seconds"] = {
            "per_stage": {s: _summary(v) for s, v in latency_stage_vals.items()},
            "total_by_asr_device": {d: _summary(v) for d, v in latency_by_device.items()},
        }
        report["configs"][config.label] = cfg_block

    return report


def _write_reports(report: dict[str, Any], anchor: dict[str, Any] | None) -> tuple[str, str]:
    out_dir = reports_dir()
    ts = time.strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(out_dir, f"extraction_eval_{ts}.json")
    full = {"extraction": report, "anchor_filter": anchor}
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(full, f, indent=2)

    md_path = os.path.join(out_dir, f"extraction_eval_{ts}.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(_render_markdown(report, anchor))
    return json_path, md_path


def _fmt(s: dict[str, Any]) -> str:
    return f"{s['mean']:.3f} ± {s['std']:.3f}"


def _render_markdown(report: dict[str, Any], anchor: dict[str, Any] | None) -> str:
    lines = ["# Extraction evaluation (thesis Chapter 5)", ""]
    lines.append(f"Name-match tolerance θ = {report.get('theta')}")
    lines.append("")
    for cfg_label, cfg in report.get("configs", {}).items():
        lines.append(f"## Config: `{cfg_label}`")
        lines.append("")
        lines.append("### Per-group (mean over videos, mean ± std over runs)")
        lines.append("")
        lines.append("| Group | Precision | Recall | F1 | Category acc. | Geo mean (km) | Geo median (km) |")
        lines.append("|---|---|---|---|---|---|---|")
        for group, gb in cfg.get("groups", {}).items():
            geo = gb["geodesic_km"]
            geo_mean = f"{geo['mean']:.2f}" if geo["mean"] is not None else "—"
            geo_med = f"{geo['median']:.2f}" if geo["median"] is not None else "—"
            lines.append(
                f"| {group} ({gb['label']}) | {_fmt(gb['precision'])} | {_fmt(gb['recall'])} | "
                f"{_fmt(gb['f1'])} | {_fmt(gb['category_accuracy'])} | {geo_mean} | {geo_med} |"
            )
        lines.append("")
        fails = cfg.get("failures", {})
        if fails:
            lines.append("### Failure classes")
            lines.append("")
            for k, v in sorted(fails.items()):
                lines.append(f"- `{k}`: {v}")
            lines.append("")
        lat = cfg.get("latency_seconds", {})
        per_stage = lat.get("per_stage", {})
        dev = lat.get("total_by_asr_device", {})
        if per_stage or dev:
            lines.append("### Pipeline latency (seconds, mean ± std)")
            lines.append("")
            if per_stage:
                lines.append("| Stage | Seconds |")
                lines.append("|---|---|")
                for stage in ("download", "asr", "ocr", "consolidation", "postprocess"):
                    if stage in per_stage:
                        lines.append(f"| {stage} | {_fmt(per_stage[stage])} |")
                lines.append("")
            if dev:
                lines.append("End-to-end total by ASR device / mode:")
                for d, s in dev.items():
                    lines.append(f"- `{d}`: {_fmt(s)} s")
                lines.append("")

    if anchor:
        lines.append("## Anchor-city filter performance")
        lines.append("")
        agg = anchor.get("aggregate", {})
        lines.append(f"- Removal precision: {agg.get('removal_precision', 0):.3f}")
        lines.append(f"- Recall: {agg.get('recall', 0):.3f}")
        lines.append(f"- F1: {agg.get('f1', 0):.3f}")
        lines.append(
            f"- A_pre (genuine anchor rows): {agg.get('a_pre', 0)}; "
            f"removed: {agg.get('removed_total', 0)}"
        )
        lines.append("")
    return "\n".join(lines)


def _run_anchor_eval(path: str | None) -> dict[str, Any] | None:
    path = path or anchor_filter_eval.default_fixture_path()
    if not os.path.isfile(path):
        logger.info("anchor fixture not found at %s; skipping anchor eval", path)
        return None
    cases = anchor_filter_eval.load_anchor_cases(path)
    total, per_case = anchor_filter_eval.evaluate_anchor_cases(cases)
    return {
        "aggregate": {
            "removal_precision": total.removal_precision,
            "recall": total.recall,
            "f1": total.f1,
            "a_pre": total.a_pre,
            "removed_total": total.removed_total,
            "true_removed": total.true_removed,
            "false_removed": total.false_removed,
            "missed": total.missed,
        },
        "per_case": {
            vid: {
                "removal_precision": c.removal_precision,
                "recall": c.recall,
                "true_removed": c.true_removed,
                "false_removed": c.false_removed,
                "missed": c.missed,
            }
            for vid, c in per_case
        },
    }


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ap = argparse.ArgumentParser(description="Extraction pipeline evaluation (thesis Chapter 5).")
    ap.add_argument("--manifest", default=None, help="Path to videos.json corpus manifest.")
    ap.add_argument("--mode", default="remote", choices=["remote", "local"],
                    help="remote: call the deployed Modal backend (default). "
                         "local: re-run stages in-process (adds per-stage latency).")
    ap.add_argument("--backend-url", default=None,
                    help="Deployed backend base URL (remote mode). Defaults to env EVAL_BACKEND_URL.")
    ap.add_argument("--config-label", default="deployed",
                    help="Label for the deployed config in remote mode (e.g. 'whisper=base').")
    ap.add_argument("--configs", default="baseline",
                    help="(local mode) baseline | single-axis | full-matrix")
    ap.add_argument("--runs", type=int, default=RUNS_PER_CELL, help="Independent runs per cell.")
    ap.add_argument("--theta", type=float, default=NAME_MATCH_THETA, help="Name-match tolerance.")
    ap.add_argument("--geocode", action="store_true", help="Resolve predictions for geodesic error.")
    ap.add_argument("--anchor-fixture", default=None, help="Anchor-filter cases JSON.")
    ap.add_argument("--anchor-only", action="store_true", help="Only run the anchor-filter eval.")
    ap.add_argument("--per-video-timeout", type=int, default=600, metavar="SECONDS",
                    help="Max seconds to wait for one backend call before skipping it "
                         "and recording a timeout failure (default: 600 = 10 min).")
    ap.add_argument("--group", default=None,
                    help="Restrict to one corpus group: A (audio-only), O (ocr-only), M (mixed). "
                         "Comma-separated for multiple, e.g. --group A,O")
    ap.add_argument("--ids", default=None,
                    help="Restrict to specific video IDs, comma-separated, e.g. --ids A1,A3,M2")
    args = ap.parse_args()

    anchor = _run_anchor_eval(args.anchor_fixture)
    if args.anchor_only:
        json_path, md_path = _write_reports({"theta": args.theta, "configs": {}}, anchor)
        print(f"Anchor-filter report written:\n  {json_path}\n  {md_path}")
        return

    entries, golds = load_corpus(args.manifest, require_url=True)

    if args.group:
        allowed_groups = {g.strip().upper() for g in args.group.split(",")}
        entries = [e for e in entries if e.group in allowed_groups]
        golds = {k: v for k, v in golds.items() if k in {e.video_id for e in entries}}
        logger.info("Group filter %s → %d video(s)", sorted(allowed_groups), len(entries))

    if args.ids:
        allowed_ids = {i.strip() for i in args.ids.split(",")}
        entries = [e for e in entries if e.video_id in allowed_ids]
        golds = {k: v for k, v in golds.items() if k in {e.video_id for e in entries}}
        logger.info("ID filter %s → %d video(s)", sorted(allowed_ids), len(entries))
    if not entries:
        print("No ready videos in manifest (fill in url + gold lists). Ran anchor eval only.")
        json_path, md_path = _write_reports({"theta": args.theta, "configs": {}}, anchor)
        print(f"Report written:\n  {json_path}\n  {md_path}")
        return

    if args.mode == "remote":
        backend = RemoteBackend(args.backend_url)
        logger.info("Remote mode → %s", backend.base_url)
        configs = [ExtractionConfig(label=args.config_label)]
        runs = _run_cells_remote(entries, backend, args.runs, args.config_label,
                                 per_video_timeout=args.per_video_timeout)
    else:
        configs = _select_configs(args.configs)
        runs = asyncio.run(_run_cells(entries, configs, args.runs))

    if args.geocode:
        _geocode_predictions(runs, golds)
    report = _aggregate(runs, entries, configs, golds, args.theta)
    json_path, md_path = _write_reports(report, anchor)
    print(f"Extraction report written:\n  {json_path}\n  {md_path}")


if __name__ == "__main__":
    main()
