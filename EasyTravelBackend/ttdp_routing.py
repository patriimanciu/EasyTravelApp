"""
Tourist Trip Design Problem (TTDP) routing aligned with thesis Chapter 2.3–2.4.

Pipeline (extraction is decoupled — this module only optimizes a hand-crafted POI set):

  1. **Spatial partitioning** — ``k_means`` or ``dbscan`` on WGS84 coordinates → one cluster per trip day.
  2. **Optional priority rebalance** — spread must-see POIs across days without changing the clustering family.
  3. **Complete directed graph** per day — vertices = depot + cluster POIs; edge weights = travel time (seconds)
     from Haversine speed or an OSRM ``/table/v1`` matrix when ``travel_model=osrm``.
  4. **Construction + local improvement** — nearest-neighbor tour + 2-opt for interactive response times.

With ``travel_model=osrm``, route map geometry uses OSRM ``/route/v1`` (foot profile by default).
"""

from __future__ import annotations

import json
import logging
import math
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Sequence

import numpy as np

logger = logging.getLogger(__name__)

EARTH_RADIUS_M = 6_371_000.0
DEFAULT_OSRM_PUBLIC_URL = "https://router.project-osrm.org"


def normalize_osrm_profile(raw: str | None) -> str:
    """OSRM 5.x profile segment: ``foot`` (pedestrian), ``driving``, or ``bike``."""
    s = (raw or "foot").strip().lower()
    return s if s in ("foot", "driving", "bike") else "foot"


def _coords_close(a: tuple[float, float], b: tuple[float, float], eps: float = 1e-5) -> bool:
    return abs(a[0] - b[0]) < eps and abs(a[1] - b[1]) < eps


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in meters between two WGS84 points."""
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return EARTH_RADIUS_M * c


def travel_time_matrix_haversine(
    lats: np.ndarray,
    lons: np.ndarray,
    speed_m_s: float,
) -> np.ndarray:
    """Directed complete graph; symmetric travel times from crow-flight / assumed speed."""
    n = int(lats.shape[0])
    w = np.zeros((n, n), dtype=np.float64)
    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            d = haversine_m(float(lats[i]), float(lons[i]), float(lats[j]), float(lons[j]))
            w[i, j] = d / speed_m_s
    return w


def _osrm_table_duration_seconds(
    lats: Sequence[float],
    lons: Sequence[float],
    base_url: str,
    *,
    profile: str,
    speed_m_s: float,
    timeout_s: float = 45.0,
) -> np.ndarray | None:
    """
    OSRM /table/v1 duration matrix (seconds). ``profile`` is ``foot``, ``driving``, or ``bike``.
    Null/unreachable cells use Haversine times.
    """
    prof = normalize_osrm_profile(profile)
    n = len(lats)
    if n == 0:
        return None
    la = np.array([float(x) for x in lats], dtype=np.float64)
    lo = np.array([float(x) for x in lons], dtype=np.float64)
    h_fallback = travel_time_matrix_haversine(la, lo, speed_m_s)

    coords = ";".join(f"{float(lon)},{float(lat)}" for lat, lon in zip(lats, lons))
    url = f"{base_url.rstrip('/')}/table/v1/{prof}/{coords}?annotations=duration"
    req = urllib.request.Request(url, headers={"User-Agent": "EasyTravelBackend/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
        logger.warning("OSRM table request failed: %s", e)
        return None
    if payload.get("code") != "Ok":
        logger.warning("OSRM table code=%s", payload.get("code"))
        return None
    durations = payload.get("durations")
    if not durations or not isinstance(durations, list):
        return None
    mat = np.zeros((n, n), dtype=np.float64)
    filled = 0
    for i, row in enumerate(durations):
        if not isinstance(row, list) or len(row) != n:
            return None
        for j, v in enumerate(row):
            if i == j:
                mat[i, j] = 0.0
                continue
            if v is None or (isinstance(v, float) and (math.isnan(v) or math.isinf(v))):
                mat[i, j] = float(h_fallback[i, j])
                filled += 1
            else:
                mat[i, j] = float(v)
    if filled:
        logger.info("OSRM table: filled %d cells from Haversine fallback.", filled)
    return mat


def _osrm_route_two_points_polyline(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
    base_url: str,
    profile: str,
    *,
    timeout_s: float = 45.0,
) -> list[tuple[float, float]] | None:
    """Single OSRM leg A→B (``profile`` e.g. ``foot``). Returns [(lat, lon), ...]."""
    prof = normalize_osrm_profile(profile)
    coords = f"{float(lon1)},{float(lat1)};{float(lon2)},{float(lat2)}"
    url = f"{base_url.rstrip('/')}/route/v1/{prof}/{coords}?overview=full&geometries=geojson"
    req = urllib.request.Request(url, headers={"User-Agent": "EasyTravelBackend/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
        logger.warning("OSRM route leg request failed: %s", e)
        return None
    if payload.get("code") != "Ok":
        logger.warning("OSRM route leg code=%s", payload.get("code"))
        return None
    routes = payload.get("routes")
    if not routes or not isinstance(routes, list):
        return None
    geom = routes[0].get("geometry")
    if not isinstance(geom, dict) or geom.get("type") != "LineString":
        return None
    raw_coords = geom.get("coordinates")
    if not isinstance(raw_coords, list) or len(raw_coords) < 2:
        return None
    out: list[tuple[float, float]] = []
    for pt in raw_coords:
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            lon, lat = float(pt[0]), float(pt[1])
            out.append((lat, lon))
    return out if len(out) >= 2 else None


def fetch_osrm_route_polyline_by_legs(
    waypoint_lats: Sequence[float],
    waypoint_lons: Sequence[float],
    base_url: str,
    profile: str,
    *,
    timeout_s: float = 45.0,
    inter_leg_pause_s: float = 0.06,
) -> list[tuple[float, float]] | None:
    """
    Build the full path by chaining **pairwise** OSRM routes (same profile each leg).

    One multi-waypoint ``/route/v1`` call can produce odd paths; leg-by-leg matches how people
    actually walk between successive stops on the **foot** network.
    """
    n = len(waypoint_lats)
    if n < 2 or len(waypoint_lons) != n:
        return None
    prof = normalize_osrm_profile(profile)
    merged: list[tuple[float, float]] = []
    for i in range(n - 1):
        a_lat, a_lon = float(waypoint_lats[i]), float(waypoint_lons[i])
        b_lat, b_lon = float(waypoint_lats[i + 1]), float(waypoint_lons[i + 1])
        seg = _osrm_route_two_points_polyline(a_lat, a_lon, b_lat, b_lon, base_url, prof, timeout_s=timeout_s)
        if not seg:
            seg = [(a_lat, a_lon), (b_lat, b_lon)]
        if merged:
            if seg and _coords_close(merged[-1], seg[0]):
                merged.extend(seg[1:])
            else:
                merged.extend(seg)
        else:
            merged.extend(seg)
        if inter_leg_pause_s > 0 and i < n - 2:
            time.sleep(inter_leg_pause_s)
    return merged if len(merged) >= 2 else None


def fetch_osrm_route_polyline_lat_lon(
    waypoint_lats: Sequence[float],
    waypoint_lons: Sequence[float],
    base_url: str,
    profile: str = "foot",
    timeout_s: float = 45.0,
) -> list[tuple[float, float]] | None:
    """Backward-compatible wrapper: same as :func:`fetch_osrm_route_polyline_by_legs`."""
    return fetch_osrm_route_polyline_by_legs(
        waypoint_lats, waypoint_lons, base_url, profile, timeout_s=timeout_s
    )


def symmetrize_for_local_search(w: np.ndarray) -> np.ndarray:
    """Average with transpose so 2-opt (symmetric move) behaves predictably on road asymmetry."""
    return 0.5 * (w + w.T)


def _pick_index_by_weight(rng: np.random.Generator, weights: np.ndarray) -> int:
    """Weighted index without numpy choice(p=...) strict sum-to-1 issues."""
    n = int(weights.shape[0])
    if n <= 0:
        return 0
    w = np.nan_to_num(np.maximum(weights.astype(np.float64, copy=False), 0.0), nan=0.0, posinf=0.0, neginf=0.0)
    total = float(w.sum())
    if not math.isfinite(total) or total <= 1e-300:
        return int(rng.integers(0, n))
    thresh = float(rng.random()) * total
    csum = 0.0
    for i in range(n):
        csum += float(w[i])
        if csum >= thresh:
            return i
    return n - 1


def _recompute_centroids(labels: np.ndarray, lats: np.ndarray, lons: np.ndarray, k: int) -> np.ndarray:
    pts = np.column_stack([lats, lons])
    centroids = np.zeros((k, 2), dtype=np.float64)
    for c in range(k):
        mask = labels == c
        if mask.any():
            centroids[c] = pts[mask].mean(axis=0)
        else:
            centroids[c] = pts[0]
    return centroids


def dbscan_latlon(
    lats: np.ndarray,
    lons: np.ndarray,
    *,
    eps_m: float = 2500.0,
    min_samples: int = 2,
) -> np.ndarray:
    """
    DBSCAN on geographic points (haversine ``eps_m``). Returns labels in ``{-1, 0, 1, …}``; ``-1`` = noise.
    """
    n = int(lats.shape[0])
    labels = np.full(n, -1, dtype=np.int32)
    if n == 0:
        return labels
    eps = max(50.0, float(eps_m))
    min_pts = max(1, int(min_samples))

    neighbors: list[list[int]] = []
    for i in range(n):
        nbrs = [
            j
            for j in range(n)
            if haversine_m(float(lats[i]), float(lons[i]), float(lats[j]), float(lons[j])) <= eps
        ]
        neighbors.append(nbrs)

    cluster_id = 0
    visited = np.zeros(n, dtype=bool)
    for i in range(n):
        if visited[i]:
            continue
        visited[i] = True
        nbrs = neighbors[i]
        if len(nbrs) < min_pts:
            continue
        labels[i] = cluster_id
        queue = [x for x in nbrs if x != i]
        queued: set[int] = set(queue)
        qi = 0
        while qi < len(queue):
            j = queue[qi]
            qi += 1
            if not visited[j]:
                visited[j] = True
                if labels[j] == -1 and len(neighbors[j]) >= min_pts:
                    for x in neighbors[j]:
                        if x not in queued:
                            queued.add(x)
                            queue.append(x)
            if labels[j] == -1:
                labels[j] = cluster_id
        cluster_id += 1
    return labels


def _adjust_partition_to_k_clusters(
    labels: np.ndarray,
    lats: np.ndarray,
    lons: np.ndarray,
    k: int,
    seed: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Map variable-density DBSCAN groups (and noise) to exactly ``k`` day clusters."""
    n = int(lats.shape[0])
    k_eff = max(1, min(int(k), n))
    work = labels.astype(np.int32, copy=True)

    unique = sorted({int(x) for x in work if int(x) >= 0})
    if not unique:
        work[:] = 0
        unique = [0]

    noise = [i for i in range(n) if int(work[i]) < 0]
    if unique:
        pts = np.column_stack([lats, lons])
        cents = {c: pts[work == c].mean(axis=0) for c in unique if (work == c).any()}
        for i in noise:
            best_c = min(
                unique,
                key=lambda c: haversine_m(
                    float(lats[i]), float(lons[i]), float(cents[c][0]), float(cents[c][1])
                ),
            )
            work[i] = best_c

    relabel = {old: new for new, old in enumerate(sorted(unique))}
    for i in range(n):
        work[i] = relabel.get(int(work[i]), 0)

    c_count = len(relabel)
    rng = np.random.default_rng(seed)

    def compact() -> int:
        nonlocal work
        present = sorted({int(x) for x in set(work.tolist())})
        mapping = {old: i for i, old in enumerate(present)}
        for i in range(n):
            work[i] = mapping[int(work[i])]
        return len(present)

    while c_count > k_eff:
        pts = np.column_stack([lats, lons])
        cents = np.array([pts[work == c].mean(axis=0) for c in range(c_count)])
        best_pair = (0, 1)
        best_d = float("inf")
        for a in range(c_count):
            for b in range(a + 1, c_count):
                d = haversine_m(float(cents[a, 0]), float(cents[a, 1]), float(cents[b, 0]), float(cents[b, 1]))
                if d < best_d:
                    best_d, best_pair = d, (a, b)
        merge_from, merge_into = best_pair
        if (work == merge_from).sum() < (work == merge_into).sum():
            merge_from, merge_into = merge_into, merge_from
        work[work == merge_from] = merge_into
        c_count = compact()

    while c_count < k_eff:
        counts = [(c, int((work == c).sum())) for c in range(c_count)]
        split_c = max(counts, key=lambda t: t[1])[0]
        idxs = np.where(work == split_c)[0]
        if len(idxs) < 2:
            break
        sub_labels, _ = kmeans_latlon(lats[idxs], lons[idxs], 2, seed=int(rng.integers(0, 2_147_483_647)))
        new_id = c_count
        for local_i, gi in enumerate(idxs):
            work[gi] = split_c if int(sub_labels[local_i]) == 0 else new_id
        c_count = compact()

    labels_out = work.copy()
    if any(not (labels_out == c).any() for c in range(k_eff)):
        labels_out, _ = kmeans_latlon(lats, lons, k_eff, seed=seed)

    centroids = _recompute_centroids(labels_out, lats, lons, k_eff)
    return labels_out, centroids


def normalize_clustering_method(raw: str | None) -> str:
    m = (raw or "k_means").strip().lower().replace("-", "_")
    return m if m in ("k_means", "dbscan") else "k_means"


def cluster_pois_spatial(
    lats: np.ndarray,
    lons: np.ndarray,
    k: int,
    *,
    method: str = "k_means",
    seed: int = 42,
    dbscan_eps_m: float = 2500.0,
    dbscan_min_samples: int = 2,
) -> tuple[np.ndarray, np.ndarray, str]:
    """
    Partition POIs into ``k`` geographic clusters (one per trip day).

    ``method`` is ``k_means`` (default) or ``dbscan`` (density-based, then adjusted to ``k`` groups).
    """
    m = (method or "k_means").strip().lower().replace("-", "_")
    k_eff = max(1, min(int(k), int(lats.shape[0])))
    if m == "dbscan":
        raw = dbscan_latlon(lats, lons, eps_m=dbscan_eps_m, min_samples=dbscan_min_samples)
        labels, centroids = _adjust_partition_to_k_clusters(raw, lats, lons, k_eff, seed)
        return labels, centroids, "dbscan"
    labels, centroids = kmeans_latlon(lats, lons, k_eff, seed=seed)
    return labels, centroids, "k_means"


def kmeans_latlon(
    lats: np.ndarray,
    lons: np.ndarray,
    k: int,
    max_iter: int = 50,
    seed: int = 42,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Lloyd's algorithm on (lat, lon). Returns (labels shape (n,), centroids shape (k, 2)).
    """
    rng = np.random.default_rng(seed)
    n = lats.shape[0]
    k_eff = max(1, min(k, n))
    pts = np.column_stack([lats, lons])
    idx0 = int(rng.integers(0, n))
    centroids = np.array([pts[idx0]], dtype=np.float64)
    for _ in range(1, k_eff):
        dist2 = np.min(((pts[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=2), axis=1)
        dist2 = np.maximum(dist2.astype(np.float64, copy=False), 0.0)
        nxt = _pick_index_by_weight(rng, dist2)
        centroids = np.vstack([centroids, pts[nxt]])
    labels = np.zeros(n, dtype=np.int32)
    for _ in range(max_iter):
        dist2 = ((pts[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=2)
        new_labels = dist2.argmin(axis=1).astype(np.int32)
        if np.array_equal(new_labels, labels):
            break
        labels = new_labels
        for c in range(k_eff):
            mask = labels == c
            if mask.any():
                centroids[c] = pts[mask].mean(axis=0)
            else:
                centroids[c] = pts[rng.integers(0, n)]
    return labels, centroids


def _nearest_neighbor_tour(
    w_dir: np.ndarray,
    w_sym: np.ndarray,
    start_idx: int,
    node_indices: Sequence[int],
    return_to_start: bool,
) -> list[int]:
    """Greedy NN on w_dir; tie-break with w_sym. Visits all nodes in `node_indices` once."""
    nodes = [int(i) for i in node_indices]
    if start_idx in nodes:
        nodes.remove(start_idx)
    unvisited = set(nodes)
    tour = [start_idx]
    cur = start_idx
    while unvisited:
        best_j: int | None = None
        best_d = math.inf
        best_s = math.inf
        for j in unvisited:
            d = float(w_dir[cur, j])
            s = float(w_sym[cur, j])
            if d < best_d or (math.isclose(d, best_d) and s < best_s):
                best_d, best_s, best_j = d, s, j
        assert best_j is not None
        tour.append(best_j)
        unvisited.remove(best_j)
        cur = best_j
    if return_to_start:
        tour.append(start_idx)
    return tour


def _tour_travel_seconds_directed(tour: Sequence[int], w_dir: np.ndarray) -> float:
    return float(sum(w_dir[tour[i], tour[i + 1]] for i in range(len(tour) - 1)))


def two_opt_closed(tour: list[int], w_sym: np.ndarray) -> list[int]:
    """2-opt on a closed tour where tour[0] == tour[-1] is the depot."""
    if len(tour) < 4:
        return tour
    route = tour[:]
    while True:
        improved = False
        for i in range(1, len(route) - 2):
            for k in range(i + 1, len(route) - 1):
                if k - i == 1:
                    continue
                a, b = route[i - 1], route[i]
                c, d = route[k], route[k + 1]
                before = w_sym[a, b] + w_sym[c, d]
                after = w_sym[a, c] + w_sym[b, d]
                if after + 1e-9 < before:
                    route[i : k + 1] = list(reversed(route[i : k + 1]))
                    improved = True
        if not improved:
            break
    return route


def two_opt_open(tour: list[int], w_sym: np.ndarray) -> list[int]:
    """2-opt fixing the first vertex (start); tour is a simple path without duplicated ends."""
    if len(tour) < 4:
        return tour
    route = tour[:]
    while True:
        improved = False
        for i in range(1, len(route) - 2):
            for k in range(i + 1, len(route)):
                if k - i == 1:
                    continue
                a, b = route[i - 1], route[i]
                c, d = route[k - 1], route[k]
                before = w_sym[a, b] + w_sym[c, d]
                after = w_sym[a, c] + w_sym[b, d]
                if after + 1e-9 < before:
                    route[i:k] = list(reversed(route[i:k]))
                    improved = True
        if not improved:
            break
    return route


def route_cluster(
    local_indices: Sequence[int],
    start_local_idx: int,
    w_dir: np.ndarray,
    return_to_start: bool,
) -> list[int]:
    """Returns tour as indices into the same local matrix (includes start at ends if closed)."""
    w_sym = symmetrize_for_local_search(w_dir)
    nodes = list(local_indices)
    if return_to_start:
        nn = _nearest_neighbor_tour(w_dir, w_sym, start_local_idx, nodes, return_to_start=True)
        return two_opt_closed(nn, w_sym)
    nn = _nearest_neighbor_tour(w_dir, w_sym, start_local_idx, nodes, return_to_start=False)
    return two_opt_open(nn, w_sym)


def _poi_visit_order_from_tour(tour: list[int], start_local: int, return_to_start: bool) -> list[int]:
    """Local indices for POIs only, in visit order (excludes the virtual start vertex)."""
    if not tour:
        return []
    if return_to_start and len(tour) >= 2 and tour[0] == start_local and tour[-1] == start_local:
        body = tour[1:-1]
    else:
        body = tour[1:]
    return [int(x) for x in body if int(x) != start_local]


def _order_clusters_by_proximity_to_start(
    labels: np.ndarray,
    centroids: np.ndarray,
    start_lat: float,
    start_lon: float,
) -> list[int]:
    """Nearest-centroid-to-current chain from the trip start (greedy geographic sequencing)."""
    k = centroids.shape[0]
    order: list[int] = []
    remaining = set(range(k))
    cur_lat, cur_lon = start_lat, start_lon
    while remaining:
        best_c = min(
            remaining,
            key=lambda c: haversine_m(cur_lat, cur_lon, float(centroids[c, 0]), float(centroids[c, 1])),
        )
        order.append(best_c)
        remaining.remove(best_c)
        cur_lat, cur_lon = float(centroids[best_c, 0]), float(centroids[best_c, 1])
    return order


def planning_fields_from_visit_priority(priority: int) -> tuple[float, bool]:
    """
    Map user visit priority (1–5) to orienteering weight + mandatory flag.

    5–4: must be scheduled; 3: normal; 2–1: optional (“if there's time”), dropped first when over budget.
    Lower weight = more desirable (dropped last).
    """
    p = max(1, min(5, int(priority)))
    mandatory = p >= 4
    weight_by_priority = {5: 0.0, 4: 0.12, 3: 0.45, 2: 0.72, 1: 1.0}
    return weight_by_priority[p], mandatory


def rebalance_labels_by_priority(
    specs: Sequence["StopSpec"],
    lats: np.ndarray,
    lons: np.ndarray,
    labels: np.ndarray,
    centroids: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Post-clustering pass: spread **mandatory** POIs across days and ease crowding of low-priority optionals.
    Does not replace k-means / DBSCAN — runs after :func:`cluster_pois_spatial`.
    """
    n = int(lats.shape[0])
    k_eff = int(centroids.shape[0])
    labels = labels.astype(np.int32, copy=True)
    priorities = np.array([max(1, min(5, int(s.priority))) for s in specs], dtype=np.float64)

    def mand_count(cluster: int) -> int:
        return sum(1 for i in range(n) if int(labels[i]) == cluster and specs[i].mandatory)

    n_mand = sum(1 for s in specs if s.mandatory)
    target_mand = max(1, math.ceil(n_mand / k_eff)) if n_mand else 0

    mandatory_idxs = [i for i in range(n) if specs[i].mandatory]
    for i in sorted(mandatory_idxs, key=lambda ix: -float(priorities[ix])):
        c = int(labels[i])
        if mand_count(c) <= target_mand + 1:
            continue
        best_d = c
        best_score = float("inf")
        for d in range(k_eff):
            if d == c or mand_count(d) >= target_mand + 1:
                continue
            dist = haversine_m(
                float(lats[i]), float(lons[i]), float(centroids[d, 0]), float(centroids[d, 1])
            )
            score = dist + 3000.0 * mand_count(d)
            if score < best_score:
                best_score, best_d = score, d
        if best_d != c:
            labels[i] = best_d

    target_size = math.ceil(n / k_eff)
    optional_idxs = [i for i in range(n) if not specs[i].mandatory]
    for i in sorted(optional_idxs, key=lambda ix: float(priorities[ix])):
        if priorities[i] >= 3:
            continue
        c = int(labels[i])
        size_c = int((labels == c).sum())
        if size_c <= target_size + 1:
            continue
        best_d = c
        best_score = float("inf")
        for d in range(k_eff):
            if d == c:
                continue
            size_d = int((labels == d).sum())
            if size_d >= target_size + 2:
                continue
            dist = haversine_m(
                float(lats[i]), float(lons[i]), float(centroids[d, 0]), float(centroids[d, 1])
            )
            score = dist + 800.0 * size_d
            if score < best_score:
                best_score, best_d = score, d
        if best_d != c:
            labels[i] = best_d

    pts = np.column_stack([lats, lons])
    for c in range(k_eff):
        mask = labels == c
        if mask.any():
            centroids[c] = pts[mask].mean(axis=0)

    return labels, centroids


@dataclass(frozen=True)
class StopSpec:
    id: str
    lat: float
    lon: float
    weight: float = 1.0
    mandatory: bool = False
    service_seconds: float = 0.0
    priority: int = 3


@dataclass(frozen=True)
class DayPlan:
    day_index: int
    ordered_stop_ids: list[str]
    total_travel_seconds: float
    total_service_seconds: float
    total_seconds: float
    within_budget: bool
    dropped_stop_ids: list[str]
    # (lat, lon) samples along OSRM paths for this day (start → stops [→ start if closed]).
    route_polyline_lat_lon: tuple[tuple[float, float], ...] | None = None


def _build_augmented_matrix_with_haversine(
    lats: np.ndarray,
    lons: np.ndarray,
    start_lat: float,
    start_lon: float,
    speed_m_s: float,
) -> np.ndarray:
    n = int(lats.shape[0])
    w = np.zeros((n + 1, n + 1), dtype=np.float64)
    w[:n, :n] = travel_time_matrix_haversine(lats, lons, speed_m_s)
    for i in range(n):
        w[i, n] = haversine_m(float(lats[i]), float(lons[i]), start_lat, start_lon) / speed_m_s
        w[n, i] = haversine_m(start_lat, start_lon, float(lats[i]), float(lons[i])) / speed_m_s
    w[n, n] = 0.0
    return w


def plan_ttdp_itinerary(
    stops: Sequence[StopSpec],
    start_lat: float,
    start_lon: float,
    *,
    number_of_days: int = 1,
    daily_budget_seconds: float | None = None,
    return_to_start: bool = False,
    travel_model: str = "haversine",
    average_speed_kmh: float = 15.0,
    osrm_base_url: str | None = None,
    clustering_seed: int = 42,
    clustering_method: str = "k_means",
    dbscan_eps_m: float = 2500.0,
    dbscan_min_samples: int = 2,
    priority_rebalance: bool = True,
    accommodation_latitude: float | None = None,
    accommodation_longitude: float | None = None,
    osrm_profile: str | None = None,
) -> tuple[list[DayPlan], dict]:
    """
    Thesis pipeline: spatial cluster → (optional) priority rebalance → travel-time matrix → NN + 2-opt.

    Graph per day: V = {depot} ∪ cluster POIs, complete directed edges weighted by travel time (seconds).
    Accommodation hub forces a closed tour hub → POIs → hub each day when coordinates are set.
    """
    osrm_prof = normalize_osrm_profile(osrm_profile or os.environ.get("OSRM_PROFILE"))
    if not stops:
        return [], {
            "clustering": normalize_clustering_method(clustering_method),
            "priority_rebalance": "false",
            "routing": "nearest_neighbor_plus_2opt",
            "graph": "complete_directed_travel_time",
            "travel_model": travel_model,
            "osrm_profile": osrm_prof,
        }

    specs = list(stops)
    n = len(specs)
    lats = np.array([s.lat for s in specs], dtype=np.float64)
    lons = np.array([s.lon for s in specs], dtype=np.float64)

    hub: tuple[float, float] | None = None
    if accommodation_latitude is not None and accommodation_longitude is not None:
        hla, hlo = float(accommodation_latitude), float(accommodation_longitude)
        if (
            math.isfinite(hla)
            and math.isfinite(hlo)
            and -90.0 <= hla <= 90.0
            and -180.0 <= hlo <= 180.0
        ):
            hub = (hla, hlo)

    order_lat = float(hub[0]) if hub is not None else float(start_lat)
    order_lon = float(hub[1]) if hub is not None else float(start_lon)

    speed_m_s = max(0.5, float(average_speed_kmh)) * (1000.0 / 3600.0)
    raw_osrm = (osrm_base_url or os.environ.get("OSRM_BASE_URL") or "").strip().rstrip("/")
    route_geometry_osrm = raw_osrm or DEFAULT_OSRM_PUBLIC_URL

    used_model = "haversine"
    matrix_osrm = ""
    if travel_model.lower() == "osrm":
        matrix_osrm = raw_osrm or DEFAULT_OSRM_PUBLIC_URL
        # Probe OSRM reachability with a minimal 2-point table call rather than the full
        # n+1 matrix (which was computed and then discarded).
        probe = _osrm_table_duration_seconds(
            [float(lats[0]), order_lat],
            [float(lons[0]), order_lon],
            matrix_osrm,
            profile=osrm_prof,
            speed_m_s=speed_m_s,
        )
        if probe is not None and probe.shape[0] == 2:
            used_model = "osrm"
        else:
            logger.info("OSRM matrix unavailable; using Haversine travel times.")
            used_model = "haversine_fallback"

    days = max(1, int(number_of_days))
    labels, centroids, cluster_method = cluster_pois_spatial(
        lats,
        lons,
        min(days, n),
        method=clustering_method,
        seed=clustering_seed,
        dbscan_eps_m=dbscan_eps_m,
        dbscan_min_samples=dbscan_min_samples,
    )
    if priority_rebalance:
        labels, centroids = rebalance_labels_by_priority(specs, lats, lons, labels, centroids)
    cluster_visit_order = _order_clusters_by_proximity_to_start(labels, centroids, order_lat, order_lon)

    day_plans: list[DayPlan] = []
    current_start_lat = order_lat
    current_start_lon = order_lon
    day_counter = 0

    for c in cluster_visit_order:
        members = [i for i in range(n) if int(labels[i]) == c]
        if not members:
            continue

        working_members = members[:]
        dropped_ids: list[str] = []

        if hub is not None:
            current_start_lat, current_start_lon = hub[0], hub[1]
        effective_return = bool(return_to_start) or (hub is not None)

        def route_and_cost(ms: list[int]) -> tuple[list[int], float, float]:
            if not ms:
                return [], 0.0, 0.0
            local_lats = [float(lats[i]) for i in ms] + [current_start_lat]
            local_lons = [float(lons[i]) for i in ms] + [current_start_lon]
            m2 = len(local_lats)
            wloc = travel_time_matrix_haversine(
                np.array(local_lats, dtype=np.float64),
                np.array(local_lons, dtype=np.float64),
                speed_m_s,
            )
            if used_model == "osrm" and matrix_osrm:
                mat_loc = _osrm_table_duration_seconds(
                    local_lats, local_lons, matrix_osrm, profile=osrm_prof, speed_m_s=speed_m_s
                )
                if mat_loc is not None and mat_loc.shape[0] == m2:
                    wloc = mat_loc
            s_loc = m2 - 1
            tour_local = route_cluster(list(range(m2)), s_loc, wloc, return_to_start=effective_return)
            travel = _tour_travel_seconds_directed(tour_local, wloc)
            poi_local_order = _poi_visit_order_from_tour(tour_local, s_loc, effective_return)
            ordered_globals = [ms[li] for li in poi_local_order]
            service = float(sum(specs[g].service_seconds for g in ordered_globals))
            return ordered_globals, travel, service

        ordered_globals, travel_sec, service_sec = route_and_cost(working_members)

        if daily_budget_seconds is not None:
            optional_pool = [g for g in working_members if not specs[g].mandatory]
            while optional_pool and travel_sec + service_sec > float(daily_budget_seconds) + 1e-6:
                victim = min(
                    optional_pool,
                    key=lambda g: (specs[g].priority, specs[g].weight, -specs[g].service_seconds),
                )
                optional_pool.remove(victim)
                working_members = [g for g in working_members if g != victim]
                dropped_ids.append(specs[victim].id)
                ordered_globals, travel_sec, service_sec = route_and_cost(working_members)

        ordered_ids = [specs[g].id for g in ordered_globals]
        total = travel_sec + service_sec
        within = daily_budget_seconds is None or total <= float(daily_budget_seconds) + 1e-3

        route_poly: tuple[tuple[float, float], ...] | None = None
        if ordered_globals:
            wp_lat = [current_start_lat] + [float(lats[g]) for g in ordered_globals]
            wp_lon = [current_start_lon] + [float(lons[g]) for g in ordered_globals]
            if effective_return:
                wp_lat.append(current_start_lat)
                wp_lon.append(current_start_lon)
            raw_route = fetch_osrm_route_polyline_by_legs(
                wp_lat, wp_lon, route_geometry_osrm, osrm_prof
            )
            if raw_route:
                route_poly = tuple(raw_route)

        day_plans.append(
            DayPlan(
                day_index=day_counter,
                ordered_stop_ids=ordered_ids,
                total_travel_seconds=travel_sec,
                total_service_seconds=service_sec,
                total_seconds=total,
                within_budget=within,
                dropped_stop_ids=dropped_ids,
                route_polyline_lat_lon=route_poly,
            )
        )
        day_counter += 1

        if hub is None and ordered_globals:
            last = ordered_globals[-1]
            current_start_lat = float(lats[last])
            current_start_lon = float(lons[last])

    meta = {
        "clustering": cluster_method,
        "priority_rebalance": "true" if priority_rebalance else "false",
        "routing": "nearest_neighbor_plus_2opt",
        "graph": "complete_directed_travel_time",
        "travel_model": used_model,
        "osrm_profile": osrm_prof,
        "accommodation_hub": "true" if hub is not None else "false",
    }
    return day_plans, meta
