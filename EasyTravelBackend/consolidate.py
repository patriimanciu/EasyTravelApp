"""
FR-05: Build versioned LLM consolidation context from transcript, OCR, and captions.

NFR-07: PROMPT_TEMPLATE_VERSION is fixed here and logged per run.
"""

from __future__ import annotations

from typing import Any

# Bump when consolidation instructions change (thesis traceability).
PROMPT_TEMPLATE_VERSION = "v1.3-anchor-postfilter-note"

CONSOLIDATION_SYSTEM_PROMPT = f"""You are the consolidation module for a travel-video assistant (thesis FR-05).
Prompt template version: {PROMPT_TEMPLATE_VERSION}

Note: The API applies deterministic checks after your reply — never emit the anchor city/metro as its own Location row when the video is scoped inside that metro (others share that same `city` value).

You receive three modality channels:
- VIDEO METADATA: title and platform description/caption (FR-04).
- ASR TRANSCRIPT: speech with optional segment timestamps (FR-02).
- ON-SCREEN OCR: text read from sampled video frames; lines are deduplicated (FR-03).

Your job:
1. Extract concrete PLACES a tourist could visit or route to: venues, neighborhoods/districts, cities (when appropriate), landmarks, parks, museums, restaurants, hotels, shops.
2. Merge redundant mentions across modalities; prefer correctly spelled names when one channel has a clearer form.
3. Categories — use exactly one label such as: Museum, Restaurant, Cafe, Landmark, Park, Hotel, Shopping, Nightlife, Neighborhood, City, Other. Use **Neighborhood** for districts, quarters, or boroughs explored as areas (e.g. Shoreditch, Montmartre), not for a whole anchor city used only as backdrop.
4. **`city` field**: Put the inferred metro/city used for disambiguation on EVERY row (e.g. venues inside London → city "London"). This is metadata, not necessarily its own Location row (see scope rules below).
5. **Geographic scope — CRITICAL:** Infer the video's **scope anchor** from title, caption, and narration (phrases like "in London", "Paris guide", "things to do in Tokyo", "UK trip", "places in California").
   - If the scope is **a single city/metro** and the video lists things **inside** that place, **DO NOT** emit a separate Location whose `name` is that same anchor city (e.g. scope = London → extract museums, neighborhoods, venues; **omit** "London" as its own POI row). Still set `city` = "London" on children.
   - If the scope is **broader** (country, region, multi-city tour: UK, England, Europe, California, "Italy highlights"), **DO** emit named **cities** as Location rows when they are clearly **destinations to visit**, not merely ambient mention.
   - Multi-city examples inside one country: include each featured city as its own row with category **City** when appropriate; do not also add the country alone unless it's framed as a visitable macro destination.
6. For each location, set source_modalities to a subset of: "asr", "ocr", "caption" — only include a modality if it materially supported that place.
7. Use confidence between 0 and 1 (subjective): higher when multiple modalities agree or the name is unambiguous.
8. Contact / visit details — ONLY when explicitly stated in caption, transcript, or OCR (never invent or guess):
   - address: street or venue address string if clearly given; else null.
   - phone_number: phone or WhatsApp-style number exactly as presented; else null.
   - url: full http(s) URL or a domain clearly shown as the official site; normalize to https URL when obvious; else null.
   - opening_hours: concise free-text hours/days if stated (e.g. "Mon–Fri 9–17"); else null.

Output must match the response schema exactly (structured JSON). Do not invent places that are clearly fictional; if unsure, lower confidence or omit borderline cases."""


def build_consolidation_user_message(
    *,
    title: str,
    description: str,
    asr_block: str,
    ocr_lines: list[str],
) -> str:
    ocr_section = (
        "\n".join(f"- {line}" for line in ocr_lines)
        if ocr_lines
        else "(no on-screen text extracted — OCR empty or unavailable; continue with ASR + caption only, NFR-02)"
    )
    return (
        f"=== CONSOLIDATION REQUEST ===\n"
        f"template_version: {PROMPT_TEMPLATE_VERSION}\n\n"
        f"=== VIDEO METADATA (FR-04) ===\n"
        f"Title: {title}\n"
        f"Description / caption:\n{description or '(none)'}\n\n"
        f"{asr_block}\n\n"
        f"=== ON-SCREEN TEXT / OCR (FR-03, deduplicated) ===\n"
        f"{ocr_section}\n"
    )


def run_artifact_summary(
    *,
    asr: dict[str, Any],
    ocr_count: int,
    ocr_interval: float,
    had_video: bool,
) -> dict[str, Any]:
    return {
        "prompt_template_version": PROMPT_TEMPLATE_VERSION,
        "asr_model": asr.get("model_name"),
        "asr_device": asr.get("device"),
        "asr_segment_count": len(asr.get("segments") or []),
        "ocr_line_count": ocr_count,
        "ocr_sample_interval_sec": ocr_interval,
        "had_video_file": had_video,
    }
