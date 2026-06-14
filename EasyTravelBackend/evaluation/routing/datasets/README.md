# Routing POI datasets

POI pools backing the routing benchmark instances (thesis Section 5.2.2). Each
profile samples five instances from one dataset:

| Profile | Dataset file | Stops / day(s) |
|---|---|---|
| `dense_urban_core` | `dense_pois.json` | ~20 / 1 day |
| `medium_multi_day` | `medium_pois.json` | ~40 / 3 days |
| `large_dispersed` | `large_pois.json` | ~80 / 5 days |

## Generating the synthetic pools

```
python -m evaluation.routing.generate_datasets
```

This writes `dense_pois.json`, `medium_pois.json`, and `large_pois.json` —
seeded, area-uniform POI clouds anchored on real city centres (Paris / London /
Rome) so the public OSRM foot network returns sensible travel times.

## Using a real public dataset

Drop a file in the same schema to replace a synthetic pool:

```json
{
  "city": "London",
  "origin": { "latitude": 51.5074, "longitude": -0.1278 },
  "accommodation": { "latitude": 51.51, "longitude": -0.12 },
  "pois": [
    {
      "id": "p1",
      "name": "British Museum",
      "latitude": 51.5194,
      "longitude": -0.1270,
      "priority": 5,
      "service_time_seconds": 5400
    }
  ]
}
```

`priority` is 1–5 (5 = must-see). The pool must contain at least as many POIs as
the profile's target stop count.
