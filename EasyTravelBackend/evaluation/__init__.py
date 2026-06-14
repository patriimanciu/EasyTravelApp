"""
Empirical evaluation harness for the EasyTravel backend (thesis Chapter 5).

Two independent sub-harnesses, mirroring the chapter structure:

* ``evaluation.extraction`` — name-level precision/recall/F1, category accuracy,
  geodesic error, and anchor-city filter performance over the 15-video fixture
  corpus (Sections 5.2.1, 5.3.1).
* ``evaluation.routing`` — total travel time, optimality gap against an exact TSP
  solver, and budget satisfaction over the synthetic benchmark instances
  (Sections 5.2.2, 5.3.2).

The harness is intentionally decoupled from FastAPI: it imports the same stage
functions used by ``main.py`` so that measured behaviour matches production.
"""

__all__ = ["extraction", "routing"]
