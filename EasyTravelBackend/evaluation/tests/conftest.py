"""Put the backend root on sys.path so ``import evaluation...`` and flat backend
modules resolve when pytest is invoked from anywhere."""

import os
import sys

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)
