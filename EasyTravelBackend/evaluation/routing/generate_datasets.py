"""
Generate synthetic POI datasets for the routing benchmark (thesis Section 5.2.2).

Produces three city pools of differing size and spatial density, anchored on real
city centres so the public OSRM foot network returns sensible travel times:

* ``dense_pois.json``  — tight, high-density core (small radius, many close POIs).
* ``medium_pois.json`` — moderate spread.
* ``large_pois.json``  — dispersed across a wide area (multi-day scale).

Generation is fully seeded so the benchmark corpus is reproducible. Drop a
real public POI dataset in the same schema to use measured points instead.

Run:  python -m evaluation.routing.generate_datasets
"""

from __future__ import annotations

import json
import math
import os
import random
from dataclasses import dataclass

from .instances import datasets_dir


@dataclass(frozen=True)
class CitySpec:
    key: str
    city: str
    center_lat: float
    center_lon: float
    radius_km: float
    n_pois: int
    seed: int


# Radius and count chosen so each profile has enough POIs:
# dense (>=20), medium (>=40), large (>=80).
CITY_SPECS = (
    CitySpec("dense", "Paris", 48.8566, 2.3522, radius_km=1.8, n_pois=30, seed=42),
    CitySpec("medium", "London", 51.5074, -0.1278, radius_km=6.0, n_pois=55, seed=43),
    CitySpec("large", "Rome", 41.9028, 12.4964, radius_km=14.0, n_pois=100, seed=44),
)

# Visit priority distribution (1..5); skewed toward 3 with a few must-sees.
_PRIORITY_WEIGHTS = {1: 0.10, 2: 0.20, 3: 0.40, 4: 0.20, 5: 0.10}
# Service time per priority, seconds (higher priority ~ longer dwell).
_SERVICE_BY_PRIORITY = {1: 1200, 2: 1800, 3: 2700, 4: 3600, 5: 5400}


def _offset_latlon(lat: float, lon: float, dist_km: float, bearing_rad: float) -> tuple[float, float]:
    """Move a point by ``dist_km`` along ``bearing_rad`` (equirectangular approx)."""
    dlat = (dist_km / 111.0) * math.cos(bearing_rad)
    dlon = (dist_km / (111.0 * math.cos(math.radians(lat)))) * math.sin(bearing_rad)
    return lat + dlat, lon + dlon


def _pick_priority(rng: random.Random) -> int:
    r = rng.random()
    cum = 0.0
    for p, w in _PRIORITY_WEIGHTS.items():
        cum += w
        if r <= cum:
            return p
    return 3


def generate_dataset(spec: CitySpec) -> dict:
    rng = random.Random(spec.seed)
    pois = []
    for i in range(spec.n_pois):
        # sqrt for area-uniform sampling within the disc.
        dist = spec.radius_km * math.sqrt(rng.random())
        bearing = rng.uniform(0.0, 2 * math.pi)
        lat, lon = _offset_latlon(spec.center_lat, spec.center_lon, dist, bearing)
        prio = _pick_priority(rng)
        pois.append(
            {
                "id": f"{spec.key}_{i+1:03d}",
                "name": f"{spec.city} POI {i+1}",
                "latitude": round(lat, 6),
                "longitude": round(lon, 6),
                "priority": prio,
                "service_time_seconds": _SERVICE_BY_PRIORITY[prio],
            }
        )
    # Accommodation hub near the centre for multi-day profiles.
    hub_lat, hub_lon = _offset_latlon(spec.center_lat, spec.center_lon, spec.radius_km * 0.15, 0.7)
    return {
        "city": spec.city,
        "_comment": "Synthetic, seeded POI pool (thesis Section 5.2.2). Replace with a real public dataset in this schema to use measured points.",
        "origin": {"latitude": spec.center_lat, "longitude": spec.center_lon},
        "accommodation": {"latitude": round(hub_lat, 6), "longitude": round(hub_lon, 6)},
        "pois": pois,
    }


def main() -> None:
    out_dir = datasets_dir()
    os.makedirs(out_dir, exist_ok=True)
    for spec in CITY_SPECS:
        data = generate_dataset(spec)
        path = os.path.join(out_dir, f"{spec.key}_pois.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"wrote {path} ({len(data['pois'])} POIs around {spec.city})")


if __name__ == "__main__":
    main()
