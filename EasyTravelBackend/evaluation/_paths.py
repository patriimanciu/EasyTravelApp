"""
Make the flat backend modules (``ttdp_routing``, ``consolidate``, …) importable
from inside the ``evaluation`` package, whether it is run as a module
(``python -m evaluation.routing.run_routing_eval``) or as a script.

Import this module before importing any backend module from within evaluation.
"""

from __future__ import annotations

import os
import sys

# .../EasyTravelBackend
BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# .../EasyTravelBackend/evaluation
EVAL_DIR = os.path.join(BACKEND_DIR, "evaluation")


def ensure_backend_on_path() -> str:
    """Insert the backend root on ``sys.path`` so flat imports resolve. Idempotent."""
    if BACKEND_DIR not in sys.path:
        sys.path.insert(0, BACKEND_DIR)
    return BACKEND_DIR


ensure_backend_on_path()
