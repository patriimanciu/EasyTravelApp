"""Unit tests for the exact TSP reference (thesis Section 5.2.2)."""

from __future__ import annotations

import numpy as np
import pytest

pytest.importorskip("python_tsp")

from evaluation.routing.exact_tsp import exact_tour_cost


def _unit_square():
    pts = np.array([[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]])
    n = len(pts)
    m = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            m[i, j] = np.linalg.norm(pts[i] - pts[j])
    return m


def test_trivial_sizes():
    # n=1: cost is 0.
    assert exact_tour_cost(np.zeros((1, 1)), closed=False)[1] == 0.0

    # n=2: open path traverses the single edge.
    assert exact_tour_cost(np.array([[0., 5.], [5., 0.]]), closed=False)[1] == pytest.approx(5.0)

    # n=3 (special-case branch): equilateral triangle, closed=3, open=2.
    tri = np.array([[0., 1., 1.], [1., 0., 1.], [1., 1., 0.]])
    assert exact_tour_cost(tri, closed=True)[1] == pytest.approx(3.0)
    assert exact_tour_cost(tri, closed=False)[1] == pytest.approx(2.0)


def test_closed_tour_optimum_is_perimeter():
    m = _unit_square()
    order, cost = exact_tour_cost(m, closed=True, start_index=0)
    assert cost == pytest.approx(4.0, abs=1e-6)
    assert set(order) == {0, 1, 2, 3} and order[0] == 0


def test_open_path_cheaper_than_closed():
    m = _unit_square()
    _, closed_cost = exact_tour_cost(m, closed=True, start_index=0)
    order, open_cost = exact_tour_cost(m, closed=False, start_index=0)
    assert open_cost < closed_cost
    assert open_cost == pytest.approx(3.0, abs=1e-6)
    assert order[0] == 0


def test_start_index_respected():
    m = _unit_square()
    order, _ = exact_tour_cost(m, closed=False, start_index=2)
    assert order[0] == 2


def test_exact_cost_never_exceeds_arbitrary_path():
    m = _unit_square()
    bad_order = [0, 2, 1, 3]  # crossing tour — deliberately sub-optimal
    heur_cost = sum(m[bad_order[i], bad_order[i + 1]] for i in range(len(bad_order) - 1))
    _, opt_cost = exact_tour_cost(m, closed=False, start_index=0)
    assert opt_cost <= heur_cost + 1e-9
