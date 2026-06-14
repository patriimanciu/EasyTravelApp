"""
Routing benchmark instances (thesis Section 5.2.2, 5.3.2).

A *POI dataset* is a city-level pool of points (coordinates, priority label,
service time) plus a trip origin. Benchmark *instances* are reproducibly sampled
from a dataset for each city profile: dense urban core (n≈20, 1 day), medium
multi-day (n≈40, 3 days), large dispersed (n≈80, 5 days). Five instances per
profile are drawn with deterministic seeds so results are reproducible.
"""

from __future__ import annotations

import json
import os
import random
from dataclasses import dataclass, field
from typing import Any

from ..config import RoutingProfile


@dataclass(frozen=True)
class POI:
    id: str
    name: str
    latitude: float
    longitude: float
    priority: int = 3
    service_time_seconds: float = 0.0


@dataclass(frozen=True)
class POIDataset:
    city: str
    origin_lat: float
    origin_lon: float
    pois: list[POI]
    accommodation_lat: float | None = None
    accommodation_lon: float | None = None


@dataclass(frozen=True)
class Instance:
    instance_id: str
    profile: str
    city: str
    origin_lat: float
    origin_lon: float
    days: int
    stops: list[POI]
    daily_budget_seconds: float | None = None
    accommodation_lat: float | None = None
    accommodation_lon: float | None = None


def load_dataset(path: str) -> POIDataset:
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    origin = raw.get("origin") or {}
    pois = [
        POI(
            id=str(p.get("id") or f"poi_{i}"),
            name=str(p.get("name") or p.get("id") or f"poi_{i}"),
            latitude=float(p["latitude"]),
            longitude=float(p["longitude"]),
            priority=int(p.get("priority", 3)),
            service_time_seconds=float(p.get("service_time_seconds", 0.0)),
        )
        for i, p in enumerate(raw.get("pois", []))
    ]
    acc = raw.get("accommodation") or {}
    return POIDataset(
        city=str(raw.get("city") or "city"),
        origin_lat=float(origin.get("latitude", 0.0)),
        origin_lon=float(origin.get("longitude", 0.0)),
        pois=pois,
        accommodation_lat=(float(acc["latitude"]) if acc.get("latitude") is not None else None),
        accommodation_lon=(float(acc["longitude"]) if acc.get("longitude") is not None else None),
    )


def datasets_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "datasets")


def build_instances(
    profile: RoutingProfile,
    dataset: POIDataset,
    *,
    base_seed: int = 1000,
) -> list[Instance]:
    """
    Draw ``profile.instances`` instances of ~``profile.approx_stops`` stops each by
    seeded random sampling without replacement from the dataset pool. Each instance
    uses a distinct deterministic seed so the corpus is reproducible.
    """
    pool = dataset.pois
    n = min(profile.approx_stops, len(pool))
    if n < len(pool) // 1 and len(pool) < profile.approx_stops:
        # Not enough POIs in the dataset for this profile; caller should warn.
        pass

    instances: list[Instance] = []
    for k in range(profile.instances):
        rng = random.Random(base_seed + hash((profile.name, k)) % 100000)
        take = min(n, len(pool))
        stops = rng.sample(pool, take) if take < len(pool) else list(pool)
        instances.append(
            Instance(
                instance_id=f"{profile.name}_{k+1}",
                profile=profile.name,
                city=dataset.city,
                origin_lat=dataset.origin_lat,
                origin_lon=dataset.origin_lon,
                days=profile.days,
                stops=stops,
                daily_budget_seconds=profile.daily_budget_seconds,
                accommodation_lat=dataset.accommodation_lat,
                accommodation_lon=dataset.accommodation_lon,
            )
        )
    return instances


def dataset_path_for(profile: RoutingProfile, override: dict[str, str] | None = None) -> str:
    """Resolve which dataset file backs a profile. ``override`` maps dataset_key->path."""
    if override and profile.dataset_key in override:
        return override[profile.dataset_key]
    return os.path.join(datasets_dir(), f"{profile.dataset_key}_pois.json")
