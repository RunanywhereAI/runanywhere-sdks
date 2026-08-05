"""Result and value types returned by the namespaces, with the v3 spec's field names.

Every generation result carries the same metrics block (``input_tokens``, ``output_tokens``,
``time_to_first_token_ms``, ``tokens_per_second``, ``request_id``, ``model``) so no caller has
to compute throughput itself.
"""

from __future__ import annotations

import asyncio
import threading
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Any, Callable, Dict, Iterator, List, Optional

import numpy as np

from .inputs import AudioFormat, InferenceFramework, ModelCategory
from .options import BackendPreference, StructuredOutputMode

__all__ = [
    "AppliedAdapter",
    "Audio",
    "AudioChunk",
    "AudioFrame",
    "ClassInfo",
    "DiarizationResult",
    "Embedding",
    "FinishReason",
    "GenerationResult",
    "ImageData",
    "ImageResult",
    "LoadedModel",
    "LoraState",
    "Match",
    "ModelInfo",
    "ModelsState",
    "RagCapabilities",
    "RagResult",
    "RagStats",
    "RankedResult",
    "SDKCapabilities",
    "Segment",
    "SegmentationResult",
    "SpeakerSegment",
    "SpeechHandle",
    "StreamingCapabilities",
    "StructuredResult",
    "SttState",
    "SttStream",
    "ToolCapabilities",
    "TokenKind",
    "ToolCall",
    "Transcription",
    "UnavailableCapability",
    "VadResult",
    "VadStream",
    "Voice",
    "VoiceTurnResult",
    "Word",
]


class FinishReason(IntEnum):
    """Why generation stopped."""

    STOP = 0
    LENGTH = 1
    TOOL_CALLS = 2
    CANCELLED = 3
    CONTENT_FILTER = 4
    UNKNOWN = 5


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
    #: Backend-native finish-reason string, before normalization into ``finish_reason``.
    raw_finish_reason: Optional[str] = None
    input_tokens: int = 0
    output_tokens: int = 0
    time_to_first_token_ms: float = 0.0
    tokens_per_second: float = 0.0
    request_id: str = ""
    model: str = ""
    actual_backend: Optional[InferenceFramework] = None
    actual_device: Optional[str] = None


@dataclass
class StructuredResult:
    """A generation constrained to a JSON schema, parsed into ``value``."""

    value: Any = None
    raw: str = ""
    valid: bool = False
    mode: StructuredOutputMode = StructuredOutputMode.VALIDATION_ONLY
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
class VoiceTurnResult:
    """One completed file-PCM voice-agent turn (STT → LLM → TTS)."""

    transcription: str = ""
    response: str = ""
    audio: Audio = field(default_factory=Audio)
    speech_detected: bool = False
    stt_time_ms: int = 0
    llm_time_ms: int = 0
    tts_time_ms: int = 0
    total_time_ms: int = 0


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


class LoadedModel:
    """Resident-model ownership handle returned by ``models.load``.

    ``close()`` and ``models.unload(id)`` release the same residency; calling either after
    the other is a no-op.
    """

    def __init__(
        self,
        id: str,
        category: ModelCategory,
        *,
        requested_backend: Optional[BackendPreference] = None,
        actual_backend: Optional[InferenceFramework] = None,
        actual_device: str = "unknown",
        runtime_version: Optional[str] = None,
        abi_version: Optional[str] = None,
        fallback_reason: Optional[str] = None,
        close_handler: Callable[[str], None],
    ) -> None:
        self.id = id
        self.category = category
        self.requested_backend = requested_backend
        self.actual_backend = actual_backend
        self.actual_device = actual_device
        self.runtime_version = runtime_version
        self.abi_version = abi_version
        self.fallback_reason = fallback_reason
        self._close_handler = close_handler
        self._closed = False

    def close(self) -> None:
        """Release this model's residency. Idempotent."""
        if self._closed:
            return
        self._closed = True
        self._close_handler(self.id)

    async def aclose(self) -> None:
        """Async form of :meth:`close`."""
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self.close)


class SpeechHandle:
    """Handle to one in-flight or completed ``tts.speak``/``VoiceSession.say`` utterance."""

    def __init__(self, id: str, *, interrupt_handler: Callable[[], None]) -> None:
        self.id = id
        self._interrupt_handler = interrupt_handler
        self._interrupted = False
        self.error: Optional[BaseException] = None
        self._done = threading.Event()

    @property
    def interrupted(self) -> bool:
        """True once :meth:`interrupt` has been called."""
        return self._interrupted

    def interrupt(self) -> None:
        """Stop playback and any in-flight synthesis. Blocks until stopped."""
        self._interrupted = True
        self._interrupt_handler()
        self._mark_done()

    def wait_for_playout(self) -> None:
        """Block until playback finishes, is interrupted, or fails."""
        self._done.wait()

    async def await_playout(self) -> None:
        """Async form of :meth:`wait_for_playout`."""
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._done.wait)

    def _mark_done(self, error: Optional[BaseException] = None) -> None:
        if error is not None:
            self.error = error
        self._done.set()


@dataclass
class AudioFrame:
    """One frame of PCM audio pushed to a live :class:`SttStream`/``VadStream``."""

    samples: bytes
    sample_count: int
    timestamp_ms: Optional[int] = None


class SttStream:
    """Live speech-to-text session opened by ``stt.open_stream``.

    Establishes its audio format once; every pushed :class:`AudioFrame` carries PCM samples
    in that format.
    """

    def events(self) -> Iterator[Any]:  # pragma: no cover - interface only
        """Transcription events for this stream."""
        raise NotImplementedError

    def push_frame(self, frame: AudioFrame) -> None:  # pragma: no cover - interface only
        """Push one frame of PCM audio in the stream's established format."""
        raise NotImplementedError

    def flush(self) -> None:  # pragma: no cover - interface only
        """Request the backend surface partials for audio pushed so far."""
        raise NotImplementedError

    def finish(self) -> None:  # pragma: no cover - interface only
        """Signal that no more audio is coming; the backend finalizes the transcript."""
        raise NotImplementedError

    def close(self) -> None:  # pragma: no cover - interface only
        """Release the stream's resources. Idempotent."""
        raise NotImplementedError


class VadStream:
    """Live voice-activity session opened by ``vad.open_stream``.

    Establishes its audio format once; every pushed :class:`AudioFrame` carries PCM samples
    in that format.
    """

    def events(self) -> Iterator[Any]:  # pragma: no cover - interface only
        """Speech-activity events for this stream."""
        raise NotImplementedError

    def push_frame(self, frame: AudioFrame) -> None:  # pragma: no cover - interface only
        """Push one frame of PCM audio in the stream's established format."""
        raise NotImplementedError

    def flush(self) -> None:  # pragma: no cover - interface only
        """No-op when there is no partial-result buffer to flush."""
        raise NotImplementedError

    def finish(self) -> None:  # pragma: no cover - interface only
        """Signal that no more audio is coming; completes the event stream."""
        raise NotImplementedError

    def close(self) -> None:  # pragma: no cover - interface only
        """Release the stream's resources. Idempotent."""
        raise NotImplementedError


@dataclass
class UnavailableCapability:
    """Whether a modality/backend/feature is honestly available right now."""

    name: str
    reason: str


@dataclass
class StreamingCapabilities:
    """Per-modality streaming support, keyed by namespace name."""

    llm: bool = True
    vlm: bool = True
    stt: bool = False
    tts: bool = True
    vad: bool = True
    rag: bool = False
    images: bool = False


@dataclass
class ToolCapabilities:
    """Tool-calling support of the currently registered backends."""

    registry: bool = True
    parallel: bool = False
    cancellation: bool = True


@dataclass
class RagCapabilities:
    """RAG-session support of the currently registered backends."""

    multi_session: bool = False
    persistent: bool = False


@dataclass
class SDKCapabilities:
    """Installed, packaged, and executable surface of this SDK build.

    Generated from packaging and runtime probes rather than from IDL enum presence alone.
    :func:`runanywhere.capabilities` is the source of truth callers should consult before
    calling into a modality that might not ship on this platform.
    """

    modalities: List[str] = field(default_factory=list)
    backends: List[str] = field(default_factory=list)
    audio_formats: List[AudioFormat] = field(default_factory=list)
    streaming: StreamingCapabilities = field(default_factory=StreamingCapabilities)
    tools: ToolCapabilities = field(default_factory=ToolCapabilities)
    rag: RagCapabilities = field(default_factory=RagCapabilities)
    unavailable: List[UnavailableCapability] = field(default_factory=list)


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
