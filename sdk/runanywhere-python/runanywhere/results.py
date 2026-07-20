"""Result and value types returned by the SDK (generation, voice, models, downloads)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import NamedTuple

import numpy as np


@dataclass
class LLMGenerationResult:
    """Aggregate metrics for a completed generation (mirrors the other SDKs' result)."""

    text: str
    token_count: int
    time_to_first_token_ms: float
    tokens_per_second: float
    total_time_ms: float


@dataclass
class LLMStreamEvent:
    """A streamed generation event.

    Non-final events carry a ``token``; the final event carries an empty token,
    ``is_final=True`` and the aggregated ``LLMGenerationResult`` with timing metrics.
    """

    token: str
    is_final: bool
    result: LLMGenerationResult | None = None


class Synthesis(NamedTuple):
    """A synthesized waveform: float32 PCM samples plus their native sample rate."""

    samples: np.ndarray
    sample_rate: int


@dataclass
class VoiceTurn:
    """One voice turn: the transcript, the LLM response, and the synthesized reply."""

    transcript: str
    response: str
    audio: Synthesis


@dataclass
class ResolvedModel:
    """Concrete on-disk file paths for a resolved model."""

    id: str
    type: str
    dir: str
    primary: str
    mmproj: str | None = None


@dataclass
class DownloadProgress:
    """Byte-progress for a single file download."""

    file: str
    received: int
    total: int
    percent: int


@dataclass
class ModelStatus:
    """Downloaded state + on-disk size for a catalog model."""

    downloaded: bool
    size_bytes: int
