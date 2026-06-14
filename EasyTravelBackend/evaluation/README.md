# Evaluation harness (thesis Chapter 5)

Empirical evaluation of the two backend subsystems described in the thesis:

- **Extraction pipeline** — name-level precision/recall/F1, category accuracy,
  geodesic error, anchor-city filter performance, pipeline-latency decomposition,
  and failure-class counts over the 15-video fixture corpus (Sections 5.2.1, 5.3.1).
- **Itinerary generator** — total travel time, optimality gap against an exact TSP
  solver, and budget-satisfaction rate over synthetic benchmark instances for three
  city profiles (Sections 5.2.2, 5.3.2).

By default the harness calls the **deployed Modal backend** over HTTP (the same
`/api/process-video` and `/api/plan-itinerary` endpoints the iOS app uses), so the
evaluation exercises the real production deployment. A `local` mode is also
available for the extraction pipeline (it re-runs the stage functions in-process)
when you want the full per-stage latency decomposition.

Set the deployed URL once:

```
export EVAL_BACKEND_URL="https://YOUR-WORKSPACE--easytravel-api-serve.modal.run"
```

## Layout

```
evaluation/
  config.py                 # Table-3 config matrix, routing profiles, constants
  geocode.py                # Nominatim geocoder (geodesic ground truth, cached)
  latency.py                # per-stage timing
  extraction/
    metrics.py              # Levenshtein name match, P/R/F1, category acc, geodesic
    gold_schema.py          # gold-list + manifest schema/loader/validator
    anchor_filter_eval.py   # anchor-city filter removal precision/recall
    pipeline_runner.py      # instrumented pipeline (timing + failure classes)
    run_extraction_eval.py  # extraction evaluation CLI
    fixtures/               # videos.json manifest + gold/<id>.json + anchor cases
  routing/
    instances.py            # POI datasets + reproducible instance sampling
    generate_datasets.py    # synthetic seeded POI pools (3 cities)
    exact_tsp.py            # Held–Karp / branch-and-bound reference
    metrics.py              # travel time, optimality gap, budget satisfaction
    run_routing_eval.py     # routing evaluation CLI (k-means + DBSCAN compare)
    datasets/               # *_pois.json
  tests/                    # pytest unit tests for the metric logic
  reports/                  # generated JSON + Markdown reports (created on run)
```

## Install

```
pip install -r evaluation/requirements-eval.txt
```

(The backend runtime deps must already be installed for extraction runs.)

## Running the tests

The metric logic is unit-tested and runs with no network or model access:

```
cd EasyTravelBackend
python -m pytest evaluation/tests
```

## Extraction evaluation

1. Fill `evaluation/extraction/fixtures/videos.json` with the 15 video URLs
   (groups A / O / M) and complete each `gold/<id>.json` gold list — see
   `fixtures/README.md` for the annotation protocol.
2. Run against the deployed Modal backend (default mode):

```
cd EasyTravelBackend
export EVAL_BACKEND_URL="https://YOUR-WORKSPACE--easytravel-api-serve.modal.run"
python -m evaluation.extraction.run_extraction_eval --runs 3 --geocode
```

- `--runs`: independent runs per video (default 3) for mean ± std (LLM non-determinism).
- `--geocode`: resolve predicted names via Nominatim to compute geodesic error.
- `--config-label`: label the deployed config (e.g. `whisper=base`). To sweep the
  Table-3 knobs, redeploy Modal with the new env var and re-run with a new label.
- `--anchor-only`: score only the anchor-city filter against `anchor_filter_cases.json`
  (needs no videos or backend).


## Routing evaluation

1. Generate the synthetic POI pools (or drop real datasets in `routing/datasets/`):

```
cd EasyTravelBackend
python -m evaluation.routing.generate_datasets
```

2. Run the benchmark. Use the deployed planner with `--remote` (calls
   `/api/plan-itinerary`), or omit it to plan locally. Either way the exact-TSP
   optimality gap is computed locally; OSRM travel times use `OSRM_BASE_URL` or
   the public endpoint:

```
# against the deployed Modal planner
export EVAL_BACKEND_URL="https://YOUR-WORKSPACE--easytravel-api-serve.modal.run"
python -m evaluation.routing.run_routing_eval --profiles all --remote

# or planning locally
python -m evaluation.routing.run_routing_eval --profiles all
```

The heuristic is fixed to OSRM travel times, k-means clustering, priority
rebalance, seed 42; DBSCAN is additionally reported for the dense urban core.
Reports are written to `evaluation/reports/routing_eval_*.{json,md}`.

## Mapping to thesis sections

| Thesis | Implementation |
|---|---|
| 5.2.1 name P/R/F1 (Levenshtein θ=0.25) | `extraction/metrics.py` |
| 5.2.1 category accuracy | `extraction/metrics.py::category_accuracy` |
| 5.2.1 geodesic error | `extraction/metrics.py::geodesic_errors_km` + `geocode.py` |
| 5.2.1 anchor-city filter | `extraction/anchor_filter_eval.py` |
| 5.2.2 total travel time | `routing/metrics.py::total_travel_seconds` |
| 5.2.2 optimality gap | `routing/metrics.py` + `routing/exact_tsp.py` |
| 5.2.2 budget satisfaction | `routing/metrics.py::budget_satisfaction_rate` |
| 5.2.2 pipeline latency | `latency.py` + `extraction/pipeline_runner.py` |
| 5.3.1 config matrix / runs / failures | `config.py`, `extraction/run_extraction_eval.py` |
| 5.3.2 city profiles / exact solver | `config.py`, `routing/run_routing_eval.py` |
