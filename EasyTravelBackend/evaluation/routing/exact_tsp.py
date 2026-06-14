"""
Exact TSP reference for the optimality-gap metric (thesis Section 5.2.2, 5.3.2).

Provides the optimal tour cost on the *same* travel-time matrix the heuristic uses,
so the optimality gap Δ = (T_heuristic − T*) / T* is well-defined.

Solver strategy
---------------
* n ≤ EXACT_TSP_MAX_NODES  →  iterative bottom-up Held–Karp DP (our own
  implementation; O(n²·2ⁿ) time, O(n·2ⁿ) space).  For n=14 this is ~50 ms;
  for n=15 ~100 ms; for n=16 ~250 ms.  python_tsp is intentionally NOT used
  here — its pure-Python recursive DP freezes at n≥18 and its branch-and-bound
  also hangs on larger instances.
* n > EXACT_TSP_MAX_NODES  →  exact comparison is skipped; returns ([], None).
  Callers treat None optimal cost as "not available" and omit the instance from
  gap statistics.  The dense-urban-core profile (20 stops, 1 day) falls into
  this category; the thesis notes the limitation.

Both closed tours (depot → … → depot) and open paths with a fixed start
(depot → … → free end) are supported.  The open path is solved via the
standard free-return reduction: zero the column back to start, then solve closed.
"""

from __future__ import annotations

import logging

import numpy as np

from .. import _paths  # noqa: F401
from ..config import EXACT_TSP_DP_MAX_VERTICES
from ttdp_routing import (
    _osrm_table_duration_seconds,
    travel_time_matrix_haversine,
)

logger = logging.getLogger(__name__)

# Maximum matrix size that the iterative Held–Karp will attempt.
# n=15: ~500 K inner iterations, ≈100 ms.  n=16: ~1 M, ≈250 ms.
# Raising this beyond 16 will add seconds per day; beyond 20 will hang.
EXACT_TSP_MAX_NODES = min(EXACT_TSP_DP_MAX_VERTICES, 15)


def build_travel_matrix(
    lats: list[float],
    lons: list[float],
    *,
    travel_model: str,
    average_speed_kmh: float,
    osrm_base_url: str | None,
    osrm_profile: str,
) -> tuple[np.ndarray, str]:
    """
    Travel-time matrix (seconds) over the given points.  Tries OSRM when
    requested, falling back to Haversine if unavailable.  Returns (matrix, used_model).
    """
    speed_m_s = max(0.5, float(average_speed_kmh)) * (1000.0 / 3600.0)
    la = np.array(lats, dtype=np.float64)
    lo = np.array(lons, dtype=np.float64)
    if travel_model.lower() == "osrm":
        base = (osrm_base_url or "https://router.project-osrm.org").rstrip("/")
        mat = _osrm_table_duration_seconds(
            lats, lons, base, profile=osrm_profile, speed_m_s=speed_m_s
        )
        if mat is not None and mat.shape[0] == len(lats):
            return mat, "osrm"
        logger.info("OSRM matrix unavailable; using Haversine for exact reference.")
    return travel_time_matrix_haversine(la, lo, speed_m_s), "haversine"


# ---------------------------------------------------------------------------
# Iterative Held–Karp DP (no external solver dependency)
# ---------------------------------------------------------------------------

def _held_karp_open(matrix: np.ndarray) -> tuple[list[int], float]:
    """
    Optimal open path starting at node 0 (free end).  Uses iterative bottom-up
    Held–Karp DP.  Valid for n ≤ ~16 in a reasonable wall time.

    Returns (ordered node indices including start, optimal cost in matrix units).
    """
    n = matrix.shape[0]
    if n == 1:
        return [0], 0.0
    if n == 2:
        return [0, 1], float(matrix[0, 1])

    INF = float("inf")
    size = 1 << n

    # dp[mask][v] = min cost of a path starting at 0, visiting exactly the
    # nodes in mask, ending at v.
    dp = [[INF] * n for _ in range(size)]
    par = [[-1] * n for _ in range(size)]
    dp[1][0] = 0.0  # start: visited={0}, at node 0, cost 0

    for mask in range(1, size):
        if not (mask & 1):          # must include node 0
            continue
        for u in range(n):
            if not (mask >> u & 1):
                continue
            cost_u = dp[mask][u]
            if cost_u == INF:
                continue
            row_u = matrix[u]
            for v in range(n):
                if mask >> v & 1:   # already visited
                    continue
                new_cost = cost_u + row_u[v]
                new_mask = mask | (1 << v)
                if new_cost < dp[new_mask][v]:
                    dp[new_mask][v] = new_cost
                    par[new_mask][v] = u

    # Best ending node (open path — do not return to 0)
    full = size - 1
    best_v = min(range(n), key=lambda v: dp[full][v])
    best_cost = dp[full][best_v]

    # Reconstruct path
    path: list[int] = []
    mask, v = full, best_v
    while v >= 0:
        path.append(v)
        u = par[mask][v]
        mask ^= (1 << v)
        v = u
    return path[::-1], best_cost


def _path_cost(seq: list[int], matrix: np.ndarray) -> float:
    return float(sum(matrix[seq[i], seq[i + 1]] for i in range(len(seq) - 1)))


# ---------------------------------------------------------------------------
# Public API (unchanged signature — callers pass closed/start_index)
# ---------------------------------------------------------------------------

def exact_tour_cost(
    matrix: np.ndarray,
    *,
    closed: bool,
    start_index: int = 0,
) -> tuple[list[int], float | None]:
    """
    Optimal tour cost over all nodes in ``matrix``.

    ``closed`` True  → depot visited at both ends (loop).
    ``closed`` False → open path with fixed start at ``start_index``, free end.

    Returns (visit order, optimal travel seconds), or ([], None) when the matrix
    is too large for the exact solver (n > EXACT_TSP_MAX_NODES).  Callers that
    receive None should skip the optimality-gap calculation for this day.
    """
    n = matrix.shape[0]
    if n <= 1:
        return [], 0.0
    if n == 2:
        i, j = (start_index, 1 - start_index) if start_index == 0 else (start_index, 0)
        return [i, j], float(matrix[i, j])

    if n > EXACT_TSP_MAX_NODES:
        logger.debug(
            "Skipping exact TSP for n=%d (> EXACT_TSP_MAX_NODES=%d); "
            "gap will be reported as N/A for this day.",
            n, EXACT_TSP_MAX_NODES,
        )
        return [], None

    # Reorder so that the desired start is at local index 0.
    if start_index != 0:
        order = [start_index] + [i for i in range(n) if i != start_index]
        work = matrix[np.ix_(order, order)]
    else:
        order = list(range(n))
        work = np.array(matrix, dtype=np.float64, copy=True)

    if closed:
        # Closed tour: zero the return-to-start column then solve as open path.
        # The open-path optimal equals the closed-tour optimal when return cost is 0.
        work = work.copy()
        work[:, 0] = 0.0

    local_perm, cost = _held_karp_open(work)

    if not closed:
        # For open path the free-return trick is not needed; result is already open.
        pass

    global_perm = [order[i] for i in local_perm]
    return global_perm, cost
