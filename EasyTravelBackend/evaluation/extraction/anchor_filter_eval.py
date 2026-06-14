"""
Anchor-city filter performance (thesis Section 5.2.1, "Anchor-city filter performance").

The postprocess module ``strip_redundant_anchor_city_rows`` removes rows whose name
duplicates the video's scope-anchor city. We evaluate it against a hand-labelled
set of anchor-city rows in the fixture outputs:

* removal precision = (removed rows that were genuine anchor-city emissions) / (all removed rows)
* filter recall     = (genuine anchor-city emissions removed) / (all genuine anchor-city emissions)

A *fixture case* is the raw LLM location list for one video (before postprocess),
the title/description, and a boolean ``should_remove`` label per row.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from types import SimpleNamespace
from typing import Any, Sequence

from .. import _paths  # noqa: F401  (ensures backend modules are importable)
from location_postprocess import strip_redundant_anchor_city_rows


@dataclass
class AnchorRow:
    name: str
    city: str | None
    should_remove: bool  # gold label: is this a genuine anchor-city emission?

    def as_location(self) -> SimpleNamespace:
        # Duck-typed object with .name and .city, matching what the filter reads.
        return SimpleNamespace(name=self.name, city=self.city)


@dataclass
class AnchorCase:
    video_id: str
    title: str
    description: str
    rows: list[AnchorRow]


@dataclass
class AnchorConfusion:
    """Confusion counts for one case or aggregated across cases."""

    true_removed: int = 0   # removed AND should_remove  (TP)
    false_removed: int = 0  # removed AND NOT should_remove (FP)
    missed: int = 0         # NOT removed AND should_remove (FN)
    kept_correct: int = 0   # NOT removed AND NOT should_remove (TN)

    @property
    def a_pre(self) -> int:
        """Genuine anchor-city rows present before postprocess (A_pre)."""
        return self.true_removed + self.missed

    @property
    def removed_total(self) -> int:
        return self.true_removed + self.false_removed

    @property
    def removal_precision(self) -> float:
        return self.true_removed / self.removed_total if self.removed_total else 1.0

    @property
    def recall(self) -> float:
        genuine = self.true_removed + self.missed
        return self.true_removed / genuine if genuine else 1.0

    @property
    def f1(self) -> float:
        p, r = self.removal_precision, self.recall
        return (2 * p * r / (p + r)) if (p + r) else 0.0

    def __add__(self, other: "AnchorConfusion") -> "AnchorConfusion":
        return AnchorConfusion(
            true_removed=self.true_removed + other.true_removed,
            false_removed=self.false_removed + other.false_removed,
            missed=self.missed + other.missed,
            kept_correct=self.kept_correct + other.kept_correct,
        )


def evaluate_anchor_case(case: AnchorCase) -> AnchorConfusion:
    """Run the production filter on one case and score removals against gold labels."""
    locations = [r.as_location() for r in case.rows]
    kept = strip_redundant_anchor_city_rows(
        list(locations), title=case.title, description=case.description
    )
    kept_ids = {id(obj) for obj in kept}

    conf = AnchorConfusion()
    for row, loc in zip(case.rows, locations, strict=True):
        removed = id(loc) not in kept_ids
        if removed and row.should_remove:
            conf.true_removed += 1
        elif removed and not row.should_remove:
            conf.false_removed += 1
        elif not removed and row.should_remove:
            conf.missed += 1
        else:
            conf.kept_correct += 1
    return conf


def evaluate_anchor_cases(cases: Sequence[AnchorCase]) -> tuple[AnchorConfusion, list[tuple[str, AnchorConfusion]]]:
    """Aggregate confusion over cases; also return per-case breakdown."""
    total = AnchorConfusion()
    per_case: list[tuple[str, AnchorConfusion]] = []
    for case in cases:
        c = evaluate_anchor_case(case)
        per_case.append((case.video_id, c))
        total = total + c
    return total, per_case


# ---------------------------------------------------------------------------
# Fixture loading
# ---------------------------------------------------------------------------


def load_anchor_cases(path: str) -> list[AnchorCase]:
    """
    Load anchor-filter fixtures from JSON:

    {
      "cases": [
        {
          "video_id": "M3",
          "title": "...", "description": "...",
          "rows": [
            {"name": "London", "city": "London", "should_remove": true},
            {"name": "Tate Modern", "city": "London", "should_remove": false}
          ]
        }
      ]
    }
    """
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    if not isinstance(raw, dict) or not isinstance(raw.get("cases"), list):
        raise ValueError(f"{path}: expected object with a 'cases' array")
    cases: list[AnchorCase] = []
    for i, c in enumerate(raw["cases"]):
        rows = [
            AnchorRow(
                name=str(r["name"]),
                city=(str(r["city"]) if r.get("city") else None),
                should_remove=bool(r.get("should_remove", False)),
            )
            for r in c.get("rows", [])
        ]
        cases.append(
            AnchorCase(
                video_id=str(c.get("video_id") or f"case{i}"),
                title=str(c.get("title") or ""),
                description=str(c.get("description") or ""),
                rows=rows,
            )
        )
    return cases


def default_fixture_path() -> str:
    return os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "fixtures", "anchor_filter_cases.json"
    )
