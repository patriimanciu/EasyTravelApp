"""
Extraction metrics (thesis Section 5.2.1).

Implements, for a single video:

* Name-level precision / recall / F1 via tolerant Levenshtein matching
  (theta = 0.25 of the longer string), each gold name matched at most once.
* Category accuracy on the matched true-positive subset.
* Geodesic error (great-circle km) between predicted and ground-truth coordinates.

All functions are pure and side-effect free so they can be unit-tested without
network or model access (thesis Section 3.6, per-stage tests).
"""

from __future__ import annotations

import math
import unicodedata
from dataclasses import dataclass, field
from typing import Sequence

# ---------------------------------------------------------------------------
# String distance
# ---------------------------------------------------------------------------


def levenshtein(a: str, b: str) -> int:
    """Classic Levenshtein edit distance (insertions, deletions, substitutions)."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
        prev = cur
    return prev[-1]


def normalize_name(name: str) -> str:
    """
    Casefold, strip accents, collapse whitespace, and drop a leading ``the``.

    Keeps matching robust to trivial ASR/OCR formatting differences without being
    so aggressive that distinct venues collapse together.
    """
    s = unicodedata.normalize("NFKD", name or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.casefold().strip()
    s = " ".join(s.split())
    if s.startswith("the "):
        s = s[4:]
    return s


def name_matches(pred: str, gold: str, theta: float = 0.25) -> bool:
    """
    True positive condition (Section 5.2.1): edit(p, g) <= theta * max(|p|, |g|).

    Comparison is on normalized strings; the length normalizer uses the
    normalized strings so the tolerance scales with the compared tokens.
    """
    p = normalize_name(pred)
    g = normalize_name(gold)
    if not p and not g:
        return True
    longest = max(len(p), len(g))
    if longest == 0:
        return False
    return levenshtein(p, g) <= theta * longest


# ---------------------------------------------------------------------------
# Matching gold and predicted name sets
# ---------------------------------------------------------------------------


@dataclass
class GoldName:
    """A gold POI for matching. ``alternatives`` are accepted as valid matches."""

    name: str
    category: str = ""
    city: str | None = None
    country: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    alternatives: list[str] = field(default_factory=list)

    def all_names(self) -> list[str]:
        return [self.name, *self.alternatives]


@dataclass
class PredName:
    name: str
    category: str = ""
    city: str | None = None
    latitude: float | None = None
    longitude: float | None = None


@dataclass
class MatchResult:
    """Outcome of matching one prediction set against one gold set."""

    matched_pairs: list[tuple[int, int]]  # (pred_index, gold_index)
    false_positive_pred_indices: list[int]
    false_negative_gold_indices: list[int]
    n_pred: int
    n_gold: int

    @property
    def tp(self) -> int:
        return len(self.matched_pairs)

    @property
    def fp(self) -> int:
        return len(self.false_positive_pred_indices)

    @property
    def fn(self) -> int:
        return len(self.false_negative_gold_indices)

    @property
    def precision(self) -> float:
        return self.tp / self.n_pred if self.n_pred else 0.0

    @property
    def recall(self) -> float:
        return self.tp / self.n_gold if self.n_gold else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return (2 * p * r / (p + r)) if (p + r) else 0.0


def _match_cost(pred: str, gold_variants: Sequence[str], theta: float) -> float | None:
    """Best (lowest) normalized edit ratio among gold variants, or None if no variant matches."""
    p = normalize_name(pred)
    best: float | None = None
    for g_raw in gold_variants:
        g = normalize_name(g_raw)
        longest = max(len(p), len(g))
        if longest == 0:
            continue
        ratio = levenshtein(p, g) / longest
        if ratio <= theta and (best is None or ratio < best):
            best = ratio
    return best


def match_names(
    preds: Sequence[PredName],
    golds: Sequence[GoldName],
    theta: float = 0.25,
) -> MatchResult:
    """
    Greedy one-to-one matching: pair each prediction with the closest still-unmatched
    gold whose tolerant edit condition holds. Pairs are committed in increasing edit
    ratio so the best (lowest-distance) matches win, ensuring each gold is used once.
    """
    candidates: list[tuple[float, int, int]] = []
    for pi, pred in enumerate(preds):
        for gi, gold in enumerate(golds):
            cost = _match_cost(pred.name, gold.all_names(), theta)
            if cost is not None:
                candidates.append((cost, pi, gi))
    candidates.sort(key=lambda t: (t[0], t[1], t[2]))

    used_pred: set[int] = set()
    used_gold: set[int] = set()
    matched: list[tuple[int, int]] = []
    for _cost, pi, gi in candidates:
        if pi in used_pred or gi in used_gold:
            continue
        used_pred.add(pi)
        used_gold.add(gi)
        matched.append((pi, gi))

    fp = [pi for pi in range(len(preds)) if pi not in used_pred]
    fn = [gi for gi in range(len(golds)) if gi not in used_gold]
    return MatchResult(
        matched_pairs=matched,
        false_positive_pred_indices=fp,
        false_negative_gold_indices=fn,
        n_pred=len(preds),
        n_gold=len(golds),
    )


# ---------------------------------------------------------------------------
# Category accuracy
# ---------------------------------------------------------------------------


def normalize_category(cat: str) -> str:
    return (cat or "").strip().casefold()


def category_accuracy(
    preds: Sequence[PredName],
    golds: Sequence[GoldName],
    match: MatchResult,
) -> tuple[float, int, int]:
    """
    Fraction of matched true positives whose category agrees with the gold label
    (Section 5.2.1). Returns (accuracy, correct, total_matched_with_gold_category).

    Pairs where the gold has no category label are excluded from the denominator.
    """
    correct = 0
    total = 0
    for pi, gi in match.matched_pairs:
        gold_cat = normalize_category(golds[gi].category)
        if not gold_cat:
            continue
        total += 1
        if normalize_category(preds[pi].category) == gold_cat:
            correct += 1
    return (correct / total if total else 0.0), correct, total


# ---------------------------------------------------------------------------
# Geodesic error
# ---------------------------------------------------------------------------

_EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in kilometres between two WGS84 points."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return _EARTH_RADIUS_KM * 2 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def geodesic_errors_km(
    preds: Sequence[PredName],
    golds: Sequence[GoldName],
    match: MatchResult,
) -> list[float]:
    """
    Per-true-positive great-circle distance (km) between the predicted coordinate
    and the gold ground-truth coordinate. Only pairs where *both* coordinates are
    available contribute (Section 5.2.1, "successfully resolves to coordinates").
    """
    errors: list[float] = []
    for pi, gi in match.matched_pairs:
        p, g = preds[pi], golds[gi]
        if None in (p.latitude, p.longitude, g.latitude, g.longitude):
            continue
        errors.append(haversine_km(p.latitude, p.longitude, g.latitude, g.longitude))
    return errors


# ---------------------------------------------------------------------------
# Per-video metric bundle + aggregation
# ---------------------------------------------------------------------------


@dataclass
class VideoMetrics:
    video_id: str
    group: str
    precision: float
    recall: float
    f1: float
    tp: int
    fp: int
    fn: int
    category_accuracy: float
    category_correct: int
    category_total: int
    geodesic_errors_km: list[float]

    @property
    def mean_geodesic_km(self) -> float | None:
        return mean(self.geodesic_errors_km) if self.geodesic_errors_km else None

    @property
    def median_geodesic_km(self) -> float | None:
        return median(self.geodesic_errors_km) if self.geodesic_errors_km else None


def evaluate_video(
    video_id: str,
    group: str,
    preds: Sequence[PredName],
    golds: Sequence[GoldName],
    theta: float = 0.25,
) -> VideoMetrics:
    match = match_names(preds, golds, theta=theta)
    cat_acc, cat_correct, cat_total = category_accuracy(preds, golds, match)
    geo = geodesic_errors_km(preds, golds, match)
    return VideoMetrics(
        video_id=video_id,
        group=group,
        precision=match.precision,
        recall=match.recall,
        f1=match.f1,
        tp=match.tp,
        fp=match.fp,
        fn=match.fn,
        category_accuracy=cat_acc,
        category_correct=cat_correct,
        category_total=cat_total,
        geodesic_errors_km=geo,
    )


# ---------------------------------------------------------------------------
# Small stats helpers (kept dependency-free for unit testing)
# ---------------------------------------------------------------------------


def mean(xs: Sequence[float]) -> float:
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def stddev(xs: Sequence[float]) -> float:
    """Population standard deviation (0 for fewer than two samples)."""
    xs = list(xs)
    if len(xs) < 2:
        return 0.0
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs))


def median(xs: Sequence[float]) -> float:
    xs = sorted(xs)
    n = len(xs)
    if n == 0:
        return 0.0
    mid = n // 2
    if n % 2:
        return xs[mid]
    return (xs[mid - 1] + xs[mid]) / 2.0
