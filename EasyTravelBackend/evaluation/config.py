"""
Experimental configuration for the evaluation harness (thesis Sections 5.3, 3.6).

The extraction configuration matrix reproduces Table 3 (``tab:ch3-test-config``):
the knobs toggled across runs and their tested values. A *cell* of the experiment
is one (video, configuration) pair; each cell is executed for ``RUNS_PER_CELL``
independent runs to surface LLM non-determinism (Section 5.3.1).
"""

from __future__ import annotations

import itertools
import os
from dataclasses import dataclass, field, asdict
from typing import Any

# Number of independent runs per (video, configuration) cell. Means and standard
# deviations are reported across these runs (Section 5.3.1).
RUNS_PER_CELL = 3

# Levenshtein tolerance for name-level matching (Section 5.2.1, theta).
NAME_MATCH_THETA = 0.25

# Extraction fixture corpus groups (Section 5.2.1).
EXTRACTION_GROUPS = ("A", "O", "M")  # Audio-only, OCR-only, Mixed
GROUP_LABELS = {
    "A": "audio-only",
    "O": "ocr-only",
    "M": "mixed",
}


@dataclass(frozen=True)
class ExtractionConfig:
    """
    One column of Table 3. Values map directly onto the environment variables read
    by ``main.py`` / the stage modules, so a config can be applied by setting env.
    """

    whisper_model: str = "base"               # WHISPER_MODEL
    ocr_sample_seconds: float = 2.0           # OCR_SAMPLE_SECONDS
    ocr_max_frames: int = 45                  # OCR_MAX_FRAMES
    consolidation_model: str = "gpt-4o-mini"  # OPENAI_CONSOLIDATION_MODEL
    prompt_template_version: str = "current"  # PROMPT_TEMPLATE_VERSION (label only)
    label: str = "default"

    def env_overrides(self) -> dict[str, str]:
        return {
            "WHISPER_MODEL": str(self.whisper_model),
            "OCR_SAMPLE_SECONDS": str(self.ocr_sample_seconds),
            "OCR_MAX_FRAMES": str(self.ocr_max_frames),
            "OPENAI_CONSOLIDATION_MODEL": str(self.consolidation_model),
        }

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


# Table 3 values. The default (baseline) cell first, then single-axis sweeps so
# that the effect of each knob is isolated (everything else held fixed).
TABLE3_VALUES: dict[str, list[Any]] = {
    "whisper_model": ["base", "small"],
    "ocr_sample_seconds": [1.0, 2.0, 4.0],
    "ocr_max_frames": [30, 45, 90],
    "consolidation_model": ["gpt-4o-mini"],
    "prompt_template_version": ["current", "previous"],
}

BASELINE = ExtractionConfig(
    whisper_model="base",
    ocr_sample_seconds=2.0,
    ocr_max_frames=45,
    consolidation_model="gpt-4o-mini",
    prompt_template_version="current",
    label="baseline",
)


def single_axis_configs() -> list[ExtractionConfig]:
    """
    One config per non-baseline value of each Table-3 axis (baseline fixed for
    the other axes). This is the matched-pairs design from Section 5.3.1, and is
    far cheaper than the full Cartesian product while still isolating each effect.
    """
    configs: list[ExtractionConfig] = [BASELINE]
    seen = {(BASELINE.whisper_model, BASELINE.ocr_sample_seconds,
             BASELINE.ocr_max_frames, BASELINE.consolidation_model,
             BASELINE.prompt_template_version)}
    base = BASELINE
    for axis, values in TABLE3_VALUES.items():
        for v in values:
            kwargs = base.as_dict()
            kwargs[axis] = v
            kwargs["label"] = f"{axis}={v}"
            key = (kwargs["whisper_model"], kwargs["ocr_sample_seconds"],
                   kwargs["ocr_max_frames"], kwargs["consolidation_model"],
                   kwargs["prompt_template_version"])
            if key in seen:
                continue
            seen.add(key)
            configs.append(ExtractionConfig(**kwargs))
    return configs


def full_matrix_configs() -> list[ExtractionConfig]:
    """Full Cartesian product of Table 3 (expensive — only for exhaustive runs)."""
    axes = list(TABLE3_VALUES.keys())
    out: list[ExtractionConfig] = []
    for combo in itertools.product(*(TABLE3_VALUES[a] for a in axes)):
        kwargs = dict(zip(axes, combo))
        kwargs["label"] = ",".join(f"{a}={kwargs[a]}" for a in axes)
        out.append(ExtractionConfig(**kwargs))
    return out


# ---------------------------------------------------------------------------
# Routing experiment profiles (Section 5.3.2).
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class RoutingProfile:
    name: str
    approx_stops: int
    days: int
    instances: int = 5
    dataset_key: str = ""           # which POI dataset to sample from
    daily_budget_seconds: float | None = None
    compare_dbscan: bool = False    # Section 5.3.2: DBSCAN reported for dense core


ROUTING_PROFILES: tuple[RoutingProfile, ...] = (
    RoutingProfile(
        name="dense_urban_core",
        # 12 stops, 1 day, no budget → planner visits all 12 stops → per-day matrix
        # has 13 nodes (12 stops + origin) → Held–Karp exact solver always feasible.
        approx_stops=12,
        days=1,
        instances=5,
        dataset_key="dense",
        daily_budget_seconds=None,
        compare_dbscan=True,
    ),
    RoutingProfile(
        name="medium_multi_day",
        # 40 stops over 3 days with 8 h budget → ~10–13 stops/day selected →
        # per-day matrix ≤ 14 nodes → exact always feasible.
        approx_stops=40,
        days=3,
        instances=5,
        dataset_key="medium",
        daily_budget_seconds=8.0 * 3600.0,
        compare_dbscan=False,
    ),
    RoutingProfile(
        name="large_dispersed",
        # 60 stops over 5 days with 8 h budget → ~12 stops/day on average →
        # per-day matrix ≤ 15 nodes in most cases → exact usually feasible.
        # (Was 80; reduced so per-day n stays within the Held–Karp limit.)
        approx_stops=60,
        days=5,
        instances=5,
        dataset_key="large",
        daily_budget_seconds=8.0 * 3600.0,
        compare_dbscan=False,
    ),
)

# Heuristic planner settings fixed across routing experiments (Section 5.3.2).
ROUTING_HEURISTIC = {
    "travel_model": "osrm",
    "clustering_method": "k_means",
    "priority_rebalance": True,
    "clustering_seed": 42,
    "osrm_profile": "foot",
}

# Custom iterative Held–Karp DP (no external solver). Measured wall times:
# n=13 ≈ 80 ms, n=14 ≈ 160 ms, n=15 ≈ 500 ms, n=16 ≈ 1.1 s.
# Set to 16: covers all dense_urban_core days (n=13) and all medium/large
# days (k-means with 8 h budget produces ≤ 16 stops/day on these datasets).
EXACT_TSP_DP_MAX_VERTICES = 16


def reports_dir() -> str:
    d = os.environ.get("EVAL_REPORTS_DIR") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "reports"
    )
    os.makedirs(d, exist_ok=True)
    return d
