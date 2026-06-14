"""
Pipeline-latency instrumentation (Section 5.2.2, "Pipeline latency").

End-to-end wall-clock time decomposed into per-stage contributions
(download, ASR, OCR, consolidation, postprocess). Whisper GPU vs CPU time is
distinguished via the device reported by the ASR stage so the benefit of the
T4 accelerator (Section 3.x, Modal) can be quantified.
"""

from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Iterator


@dataclass
class StageTimer:
    """Accumulates per-stage durations for one pipeline run."""

    stages: dict[str, float] = field(default_factory=dict)
    started_at: float = field(default_factory=time.monotonic)
    asr_device: str | None = None

    @contextmanager
    def measure(self, stage: str) -> Iterator[None]:
        t0 = time.perf_counter()
        try:
            yield
        finally:
            self.stages[stage] = self.stages.get(stage, 0.0) + (time.perf_counter() - t0)

    def record(self, stage: str, seconds: float) -> None:
        self.stages[stage] = self.stages.get(stage, 0.0) + float(seconds)

    @property
    def total_seconds(self) -> float:
        return sum(self.stages.values())

    def as_dict(self) -> dict[str, float | str | None]:
        out: dict[str, float | str | None] = dict(self.stages)
        out["total"] = self.total_seconds
        out["asr_device"] = self.asr_device
        return out
