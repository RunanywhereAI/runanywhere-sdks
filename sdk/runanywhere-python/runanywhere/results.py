"""Result and value types returned by the namespaces, with the v3 spec's field names.

Every generation result carries the same metrics block (``input_tokens``, ``output_tokens``,
``time_to_first_token_ms``, ``tokens_per_second``, ``request_id``, ``model``) so no caller has
to compute throughput itself.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Any, Dict, List, Optional

import numpy as np

from .inputs import AudioFormat, InferenceFramework, ModelCategory

__all__ = [
    "AppliedAdapter",
    "Audio",
    "AudioChunk",
    "ClassInfo",
    "DiarizationResult",
    "Embedding",
    "FinishReason",
    "GenerationResult",
    "ImageData",
    "ImageResult",
    "LoraState",
    "Match",
    "ModelInfo",
    "ModelsState",
    "RagResult",
    "RagStats",
    "RankedResult",
    "Segment",
    "SegmentationResult",
    "SpeakerSegment",
    "StructuredResult",
    "SttState",
    "TokenKind",
    "ToolCall",
    "Transcription",
    "VadResult",
    "Voice",
    "Word",
]


class FinishReason(IntEnum):
    """Why generation stopped."""

    STOP = 0
    LENGTH = 1
    TOOL_CALLS = 2
    CANCELLED = 3


class TokenKind(IntEnum):
    """Whether a streamed token is answer text or the model's thinking."""

    TEXT = 0
    THOUGHT = 1


@dataclass
class ToolCall:
    """A tool the model asked to call, with its parsed arguments."""

    name: str
    arguments: Dict[str, Any] = field(default_factory=dict)
    result: Optional[Dict[str, Any]] = None


@dataclass
class GenerationResult:
    """A completed LLM or VLM generation."""

    text: str = ""
    thinking_text: Optional[str] = None
    tool_calls: List[ToolCall] = field(default_factory=list)
    finish_reason: FinishReason = FinishReason.STOP
    input_tokens: int = 0
    output_tokens: int = 0
    time_to_first_token_ms: float = 0.0
    tokens_per_second: float = 0.0
    request_id: str = ""
    model: str = ""


@dataclass
class StructuredResult:
    """A generation constrained to a JSON schema, parsed into ``value``."""

    value: Any = None
    raw: str = ""
    valid: bool = False
    input_tokens: int = 0
    output_tokens: int = 0
    time_to_first_token_ms: float = 0.0
    tokens_per_second: float = 0.0
    request_id: str = ""
    model: str = ""


@dataclass
class Word:
    """One transcribed word with its timing."""

    text: str
    start_ms: int = 0
    end_ms: int = 0
    confidence: float = 0.0
    speaker_id: Optional[str] = None


@dataclass
class Transcription:
    """A completed transcription."""

    text: str = ""
    language: Optional[str] = None
    confidence: float = 0.0
    words: List[Word] = field(default_factory=list)
    duration_ms: int = 0


@dataclass
class Audio:
    """Synthesized audio."""

    data: bytes = b""
    sample_rate: int = 0
    format: AudioFormat = AudioFormat.PCM
    duration_ms: int = 0

    def samples(self) -> np.ndarray:
        """Decode ``data`` to float32 samples."""
        from .audio import decode_wav, pcm16_to_float32

        if self.format == AudioFormat.WAV:
            return decode_wav(self.data)[1]
        return pcm16_to_float32(np.frombuffer(self.data, dtype="<i2"))


@dataclass
class AudioChunk:
    """One chunk of a synthesis stream."""

    data: bytes
    index: int = 0
    is_final: bool = False
    sample_rate: int = 0


@dataclass
class Segment:
    """A span of speech within the input audio."""

    start_ms: int
    end_ms: int


@dataclass
class VadResult:
    """The speech/silence decision for a piece of audio."""

    is_speech: bool = False
    probability: float = 0.0
    segments: List[Segment] = field(default_factory=list)


@dataclass
class Embedding:
    """One embedding vector, tagged with the index of its input text."""

    index: int
    vector: np.ndarray


@dataclass
class RankedResult:
    """A reranked document, as an index into the input list plus its score."""

    index: int
    relevance_score: float


@dataclass
class ImageData:
    """One generated image."""

    data: bytes
    width: int = 0
    height: int = 0


@dataclass
class ImageResult:
    """A completed image generation."""

    images: List[ImageData] = field(default_factory=list)
    seed: int = 0
    steps: int = 0


@dataclass
class SpeakerSegment:
    """A span of audio attributed to one speaker."""

    speaker_id: str
    start_ms: int
    end_ms: int


@dataclass
class DiarizationResult:
    """A completed diarization."""

    segments: List[SpeakerSegment] = field(default_factory=list)
    speaker_count: int = 0


@dataclass
class ClassInfo:
    """One class present in a segmentation mask."""

    id: int
    label: str = ""
    pixel_count: int = 0


@dataclass
class SegmentationResult:
    """A completed segmentation: a per-pixel class mask plus the classes it contains."""

    class_mask: bytes = b""
    width: int = 0
    height: int = 0
    classes: List[ClassInfo] = field(default_factory=list)


@dataclass
class Match:
    """One retrieved chunk."""

    text: str
    score: float = 0.0
    metadata: Dict[str, str] = field(default_factory=dict)


@dataclass
class RagResult:
    """A grounded answer plus the chunks it was built from."""

    answer: str = ""
    sources: List[Match] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    time_to_first_token_ms: float = 0.0
    tokens_per_second: float = 0.0
    request_id: str = ""
    model: str = ""


@dataclass
class RagStats:
    """Index-level counters of a RAG session."""

    document_count: int = 0
    chunk_count: int = 0
    index_size_bytes: int = 0


@dataclass
class SttState:
    """Readiness of the speech-to-text namespace."""

    is_ready: bool = False
    model_id: Optional[str] = None
    supports_streaming: bool = False
    languages: List[str] = field(default_factory=list)


@dataclass
class Voice:
    """A synthesis voice offered by a loadable TTS model."""

    id: str
    name: str = ""
    language: str = ""


@dataclass
class ModelInfo:
    """A model known to the registry."""

    id: str
    category: ModelCategory = ModelCategory.UNKNOWN
    name: Optional[str] = None
    downloaded: bool = False
    size_bytes: int = 0
    local_path: Optional[str] = None
    framework: Optional[InferenceFramework] = None


@dataclass
class ModelsState:
    """What is resident right now, and how much room is left on disk."""

    loaded: Dict[ModelCategory, ModelInfo] = field(default_factory=dict)
    storage_used_bytes: int = 0
    storage_free_bytes: int = 0


@dataclass
class AppliedAdapter:
    """A LoRA adapter currently applied to the resident model."""

    id: str
    scale: float = 1.0


@dataclass
class LoraState:
    """The LoRA adapters currently applied."""

    applied: List[AppliedAdapter] = field(default_factory=list)


# --------------------------------------------------------------------------- internal
# Host download/resolution types. Not part of the public surface: the download layer and the
# models namespace use them, callers see ModelInfo and DownloadEvent instead.
@dataclass
class ResolvedModel:
    """Concrete on-disk file paths for a resolved model."""

    id: str
    type: str
    dir: str
    primary: str
    mmproj: Optional[str] = None


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


@dataclass
class Synthesis:
    """Raw synthesis output from the bridge: float32 samples plus their sample rate."""

    samples: np.ndarray
    sample_rate: int
