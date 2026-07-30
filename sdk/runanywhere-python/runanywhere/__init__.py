"""RunAnywhere — on-device LLM, VLM, speech, embeddings and RAG for Python.

The public surface is one ``initialize`` call plus a namespace per modality::

    import runanywhere as ra
    from runanywhere import LlmOptions

    ra.initialize()
    print(ra.llm.generate("Hello", LlmOptions(model="smollm2-135m")).text)

Verbs that block — on native decode, on a download, on disk — have an ``a``-prefixed async
twin doing the same work on the event loop (``agenerate``, ``agenerate_stream``,
``atranscribe``, ``aembed``, ``aquery``, ``aload``, …). The three stream verbs that consume a
host-side iterable of audio (``stt.transcribe_stream``, ``tts.synthesize_stream``,
``vad.detect_stream``) have no twin: they do no blocking work of their own beyond the frame
they were handed.

Importing this package does NOT load the compiled native ``_core`` extension: every module
stays importable — and testable — without a native build. The library is loaded lazily on
the first :func:`initialize`.
"""

from __future__ import annotations

from typing import Optional

from ._runtime import runtime as _runtime
from .api import (
    RagSession,
    diarization,
    embeddings,
    images,
    llm,
    lora,
    models,
    rag,
    rerank,
    segmentation,
    stt,
    tts,
    vad,
    vlm,
    voice,
)
from .errors import (
    ErrorCategory,
    ErrorCode,
    SDKException,
    as_sdk_exception,
    is_sdk_exception,
)
from .events import (
    DownloadEvent,
    DownloadEventKind,
    EventBus,
    GenerationEvent,
    GenerationEventKind,
    ImageEvent,
    ImageEventKind,
    RagEvent,
    RagEventKind,
    SdkEvent,
    SdkEventKind,
    TranscriptionEvent,
    TranscriptionEventKind,
    VadEvent,
    VadEventKind,
    VoiceAgentState,
    VoiceEvent,
    VoiceEventKind,
)
from .events import bus as events
from .inputs import (
    AudioEncoding,
    AudioFormat,
    AudioFormatSpec,
    AudioInput,
    ChatMessage,
    ImageInput,
    InferenceFramework,
    ModelCategory,
    ModelFilter,
    ModelRef,
    ModelRegistration,
    RagDocument,
    Role,
    ToolDefinition,
)
from .options import (
    DiarizationOptions,
    EmbedOptions,
    Endpointing,
    Environment,
    ImageMode,
    ImageModeKind,
    ImageOptions,
    Interruption,
    LlmOptions,
    LoadOptions,
    NormalizeMode,
    PoolingMode,
    RagConfig,
    ReasoningMode,
    ReasoningOptions,
    SegmentationOptions,
    StructuredOutput,
    SttOptions,
    ToolChoice,
    ToolChoiceMode,
    TtsOptions,
    TurnHandlingOptions,
    VadOptions,
)
from .results import (
    AppliedAdapter,
    Audio,
    AudioChunk,
    ClassInfo,
    DiarizationResult,
    Embedding,
    FinishReason,
    GenerationResult,
    ImageData,
    ImageResult,
    LoraState,
    Match,
    ModelInfo,
    ModelsState,
    RagResult,
    RagStats,
    RankedResult,
    Segment,
    SegmentationResult,
    SpeakerSegment,
    StructuredResult,
    SttState,
    TokenKind,
    ToolCall,
    Transcription,
    VadResult,
    Voice,
    Word,
)

__version__ = "0.20.12"


def initialize(
    api_key: Optional[str] = None,
    base_url: Optional[str] = None,
    environment: Environment = Environment.PRODUCTION,
) -> None:
    """Bring the SDK up; everything local inference needs happens inside this one call.

    Args:
        api_key: accepted for cross-SDK signature parity. This SDK has no control-plane
            client, so no authentication, device registration or telemetry is performed.
        base_url: accepted for the same reason, and equally unused.

    Raises:
        SDKException: the native library cannot be loaded or initialized.

    Example:
        >>> import runanywhere
        >>> runanywhere.initialize()
    """
    _runtime.initialize(api_key=api_key, base_url=base_url, environment=environment)


def reset() -> None:
    """Unload every model, close every session, and shut the native runtime down."""
    _runtime.reset()


def is_ready() -> bool:
    """True once local inference is usable."""
    return _runtime.is_ready


def version() -> str:
    """The native runtime version.

    Raises:
        SDKException: the SDK is not initialized.
    """
    return _runtime.version()


def device_id() -> str:
    """A stable id for this install, persisted under the RunAnywhere home directory.

    Raises:
        SDKException: the id file cannot be read or written.
    """
    return _runtime.device_id()


def backends() -> list:
    """The engine backends compiled into this build, e.g. ``['llamacpp', 'onnx', 'sherpa']``."""
    return _runtime.backends()


__all__ = [
    "__version__",
    # core
    "initialize",
    "reset",
    "is_ready",
    "version",
    "device_id",
    "backends",
    "events",
    "Environment",
    # namespaces
    "llm",
    "vlm",
    "stt",
    "tts",
    "vad",
    "embeddings",
    "rerank",
    "images",
    "diarization",
    "segmentation",
    "voice",
    "rag",
    "models",
    "lora",
    "RagSession",
    # inputs
    "AudioEncoding",
    "AudioFormat",
    "AudioFormatSpec",
    "AudioInput",
    "ChatMessage",
    "ImageInput",
    "InferenceFramework",
    "ModelCategory",
    "ModelFilter",
    "ModelRef",
    "ModelRegistration",
    "RagDocument",
    "Role",
    "ToolDefinition",
    # options
    "DiarizationOptions",
    "EmbedOptions",
    "Endpointing",
    "ImageMode",
    "ImageModeKind",
    "ImageOptions",
    "Interruption",
    "LlmOptions",
    "LoadOptions",
    "NormalizeMode",
    "PoolingMode",
    "RagConfig",
    "ReasoningMode",
    "ReasoningOptions",
    "SegmentationOptions",
    "StructuredOutput",
    "SttOptions",
    "ToolChoice",
    "ToolChoiceMode",
    "TtsOptions",
    "TurnHandlingOptions",
    "VadOptions",
    # results
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
    # events
    "DownloadEvent",
    "DownloadEventKind",
    "EventBus",
    "GenerationEvent",
    "GenerationEventKind",
    "ImageEvent",
    "ImageEventKind",
    "RagEvent",
    "RagEventKind",
    "SdkEvent",
    "SdkEventKind",
    "TranscriptionEvent",
    "TranscriptionEventKind",
    "VadEvent",
    "VadEventKind",
    "VoiceAgentState",
    "VoiceEvent",
    "VoiceEventKind",
    # errors
    "SDKException",
    "ErrorCode",
    "ErrorCategory",
    "is_sdk_exception",
    "as_sdk_exception",
]
