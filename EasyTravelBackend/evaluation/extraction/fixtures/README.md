# Extraction fixture corpus

This directory holds the 15-video evaluation corpus described in thesis
Section 5.2.1 and the per-video gold lists.

## Files

- `videos.json` — corpus manifest. One entry per fixture video:
  - `id` — stable id, e.g. `A1`. Prefix encodes the group.
  - `group` — `A` (audio-only), `O` (OCR-only), or `M` (mixed).
  - `url` — source video link (TikTok / Instagram / YouTube short).
  - `gold_file` — relative path to the gold list (defaults to `gold/<id>.json`).
- `gold/<id>.json` — the gold list for one video.

## Groups (Section 5.2.1)

| Group | 5 videos | Isolates |
|-------|----------|----------|
| A | venue names spoken only (no overlay, no caption) | ASR recall |
| O | venue names as on-screen overlays only | OCR recall |
| M | spoken + overlay + caption with partial redundancy | cross-modal consolidation & dedup |

## Gold-list format

```json
{
  "video_id": "A1",
  "group": "A",
  "notes": "free text",
  "pois": [
    {
      "name": "Borough Market",          // canonical name as a map service shows it
      "category": "Shopping",            // one schema category (see below)
      "city": "London",
      "country": "United Kingdom",
      "latitude": 51.5055,                // optional; needed for geodesic error
      "longitude": -0.0909,               // optional
      "alternatives": ["alt name"]        // accepted as valid matches if ambiguous
    }
  ]
}
```

Schema categories: `Museum, Restaurant, Cafe, Landmark, Park, Hotel, Shopping,
Nightlife, Neighborhood, City, Other`.

## Annotation protocol (Section 5.2.1)

1. Watch the full video; pause at each identifiable venue/location mention.
2. Record the canonical name, inferred city, and category — **without** looking at
   pipeline output.
3. For names ambiguous between two venues in the same city, list both as
   `alternatives`.
4. Coordinates are optional. Add them (from a reference map) for POIs you want to
   contribute to the geodesic-error metric.

All 15 gold files (`A1`–`A5`, `O1`–`O5`, `M1`–`M5`) are scaffolded with the
matching video URL and an empty `pois` list. Fill in the POIs you see while
watching; a video stays excluded from scoring until its `pois` list is non-empty.
