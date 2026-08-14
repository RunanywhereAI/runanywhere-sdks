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
from .api.voice import VoiceSession
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
    AcceleratorPolicy,
    BackendPreference,
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
    PoolingMode,
    RagConfig,
    RagQueryOptions,
    RagRetrievalOptions,
    ReasoningMode,
    ReasoningOptions,
    SegmentationOptions,
    StructuredOutput,
    StructuredOutputMode,
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
    AudioFrame,
    ClassInfo,
    DiarizationResult,
    Embedding,
    FinishReason,
    GenerationResult,
    ImageData,
    ImageResult,
    LoadedModel,
    LoraState,
    Match,
    ModelInfo,
    ModelsState,
    RagCapabilities,
    RagResult,
    RagStats,
    RankedResult,
    SDKCapabilities,
    Segment,
    SegmentationResult,
    SpeakerSegment,
    SpeechHandle,
    StreamingCapabilities,
    StructuredResult,
    SttState,
    SttStream,
    ToolCapabilities,
    TokenKind,
    ToolCall,
    Transcription,
    UnavailableCapability,
    VadResult,
    VadStream,
    Voice,
    VoiceTurnResult,
    Word,
)

__version__ = "0.20.19"


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


def _bound(attr: str) -> bool:
    """True iff the loaded native ``_core`` extension exports ``attr``.

    Never forces a native load: unless the SDK is already initialized this returns False,
    the same "unknown until ready" treatment :func:`capabilities` already gives
    ``backends``. So a build that has the symbol only reports it available once
    :func:`initialize` has actually loaded that build's ``_core``.
    """
    return is_ready() and hasattr(_runtime.core(), attr)


def capabilities() -> SDKCapabilities:
    """Installed, packaged, and executable surface of this SDK build.

    Generated from what ``native/module.cpp`` actually binds, not from which namespaces
    merely exist in this package. ``lora``, ``diarization``, ``segmentation``, ``voice``,
    and ``images`` are reported available only once :func:`initialize` has run and the
    loaded ``_core`` build actually exports their bindings — an SDK installed from a
    wheel built before those bindings existed (or without CoreML for images) still gets
    an honest answer here. ``rerank`` remains unbound.
    """
    lora_ok = _bound("lora_apply_proto")
    diarization_ok = _bound("load_diarization_model")
    segmentation_ok = _bound("load_segmentation_model")
    voice_ok = _bound("create_voice_agent")
    images_ok = _bound("load_diffusion_model")
    modalities = ["llm", "vlm", "stt", "tts", "vad", "embeddings", "rag", "models"]
    if lora_ok:
        modalities.append("lora")
    if diarization_ok:
        modalities.append("diarization")
    if segmentation_ok:
        modalities.append("segmentation")
    if voice_ok:
        modalities.append("voice")
    if images_ok:
        modalities.append("images")
    unavailable = [
        UnavailableCapability(
            name="stt.transcribe_stream",
            reason=(
                "native/module.cpp binds no streaming STT entry point; use "
                "stt.transcribe or stt.open_stream (which reports the same gap)"
            ),
        ),
        UnavailableCapability(
            name="tts.speak",
            reason=(
                "the Python SDK has no audio output device (numpy is its only runtime "
                "dependency); use tts.synthesize and play the bytes yourself"
            ),
        ),
        UnavailableCapability(
            name="rerank",
            reason="native/module.cpp binds no rerank entry point",
        ),
        UnavailableCapability(
            name="agents",
            reason="runanywhere.agents is not part of the v4 public API surface.",
        ),
        UnavailableCapability(
            name="wakeword",
            reason="runanywhere.wakeword is not part of the v4 public API surface.",
        ),
        UnavailableCapability(
            name="realtime",
            reason=(
                "runanywhere.realtime is not part of the v4 public API surface "
                "(no WebRTC/SIP/S2S transport namespace)."
            ),
        ),
    ]
    if not lora_ok:
        unavailable.append(
            UnavailableCapability(
                name="lora",
                reason=(
                    "not initialized yet (unknown until then)"
                    if not is_ready()
                    else "this native/_core build predates the LoRA bindings "
                    "(lora_apply_proto / lora_remove_proto / lora_list_proto are not exported by "
                    "native/module.cpp) — rebuild the native extension"
                ),
            )
        )
    if not diarization_ok:
        unavailable.append(
            UnavailableCapability(
                name="diarization",
                reason=(
                    "not initialized yet (unknown until then)"
                    if not is_ready()
                    else "this native/_core build predates the diarization bindings "
                    "(load_diarization_model / diarize are not exported by "
                    "native/module.cpp) — rebuild the native extension"
                ),
            )
        )
    if not segmentation_ok:
        unavailable.append(
            UnavailableCapability(
                name="segmentation",
                reason=(
                    "not initialized yet (unknown until then)"
                    if not is_ready()
                    else "this native/_core build predates the segmentation bindings "
                    "(load_segmentation_model / segment are not exported by "
                    "native/module.cpp) — rebuild the native extension"
                ),
            )
        )
    if not voice_ok:
        unavailable.append(
            UnavailableCapability(
                name="voice",
                reason=(
                    "not initialized yet (unknown until then)"
                    if not is_ready()
                    else "this native/_core build predates the voice-agent bindings "
                    "(create_voice_agent / process_voice_turn are not exported by "
                    "native/module.cpp) — rebuild the native extension"
                ),
            )
        )
    else:
        # File-PCM turns work; mic/speaker remain unavailable on this SDK.
        unavailable.append(
            UnavailableCapability(
                name="voice.microphone",
                reason=(
                    "the Python SDK has no microphone or speaker adapter; use "
                    "VoiceSession.process_turn with file/numpy PCM"
                ),
            )
        )
    if not images_ok:
        unavailable.append(
            UnavailableCapability(
                name="images",
                reason=(
                    "not initialized yet (unknown until then)"
                    if not is_ready()
                    else "this native/_core build has no diffusion bindings "
                    "(load_diffusion_model is only exported when RAC_HAVE_BACKEND_NEURT "
                    "is set at compile time)"
                ),
            )
        )
    return SDKCapabilities(
        modalities=modalities,
        backends=list(_runtime.backends()) if is_ready() else [],
        audio_formats=[AudioFormat.PCM, AudioFormat.WAV],
        streaming=StreamingCapabilities(
            llm=True,
            vlm=True,
            stt=False,
            tts=True,
            vad=True,
            rag=True,
            images=False,
        ),
        tools=ToolCapabilities(registry=True, parallel=False, cancellation=True),
        rag=RagCapabilities(multi_session=True, persistent=False),
        unavailable=unavailable,
    )


__all__ = [
    "__version__",
    # core
    "initialize",
    "reset",
    "is_ready",
    "version",
    "device_id",
    "backends",
    "capabilities",
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
    "VoiceSession",
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
    "AcceleratorPolicy",
    "BackendPreference",
    "DiarizationOptions",
    "EmbedOptions",
    "Endpointing",
    "ImageMode",
    "ImageModeKind",
    "ImageOptions",
    "Interruption",
    "LlmOptions",
    "LoadOptions",
    "PoolingMode",
    "RagConfig",
    "RagQueryOptions",
    "RagRetrievalOptions",
    "ReasoningMode",
    "ReasoningOptions",
    "SegmentationOptions",
    "StructuredOutput",
    "StructuredOutputMode",
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
