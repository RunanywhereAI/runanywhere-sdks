"""RunAnywhere — on-device LLM / VLM / STT / TTS / embeddings for Python.

The public surface of the SDK. Importing this package does NOT load the compiled native
``_core`` extension: every pure-Python module stays importable (and hermetically testable)
without a native build. The native library is loaded lazily on the first
``RunAnywhere.initialize()`` (via :func:`runanywhere._native.get_core`), so nothing here
imports ``_core`` at module top level.
"""

from __future__ import annotations

# NOTE: keep this module free of any `_core` import (direct or transitive) — see the
# module docstring. The client / model wrappers pull in the native layer lazily.
from .audio import (
    decode_wav,
    downsample,
    encode_wav,
    float32_to_pcm16,
    pcm16_bytes,
    pcm16_to_float32,
    rms,
)
from .catalog import CATALOG, CatalogEntry, CatalogFile, ModelType, is_catalog_id
from .chat import Chat, ChatMessage
from .client import RunAnywhere
from .download import (
    download_file,
    model_status,
    models_root,
    resolve_model,
)
from .errors import (
    ErrorCategory,
    ErrorCode,
    SDKException,
    as_sdk_exception,
    is_sdk_exception,
)
from .events import (
    EventBus,
    GenerationEvent,
    InitializedEvent,
    ModelLoadedEvent,
    ModelUnloadedEvent,
    RunAnywhereEvent,
    ServicesReadyEvent,
    ShutdownEvent,
    bus,
)
from .grammar import json_schema_to_grammar
from .models import Embedder, LLMModel, STTModel, TTSVoice, Vad, VLMModel
from .options import (
    ChatOptions,
    DownloadOptions,
    GenerateOptions,
    InitOptions,
    LoadOptions,
    VadOptions,
)
from .results import (
    DownloadProgress,
    LLMGenerationResult,
    LLMStreamEvent,
    ModelStatus,
    ResolvedModel,
    Synthesis,
    VoiceTurn,
)
from .stream_metrics import stream_with_metrics
from .structured import (
    ToolCall,
    ToolRun,
    ToolSpec,
    object_grammar,
    parse_structured,
    tool_call_prompt,
    tool_call_schema,
)
from .voice_agent import VoiceAgent

__version__ = "0.20.11"

__all__ = [
    "__version__",
    # facade
    "RunAnywhere",
    # model wrappers
    "LLMModel",
    "VLMModel",
    "Embedder",
    "STTModel",
    "TTSVoice",
    "Vad",
    # conversation
    "Chat",
    "ChatMessage",
    "VoiceAgent",
    # options
    "InitOptions",
    "GenerateOptions",
    "LoadOptions",
    "DownloadOptions",
    "VadOptions",
    "ChatOptions",
    # results / value types
    "LLMGenerationResult",
    "LLMStreamEvent",
    "Synthesis",
    "VoiceTurn",
    "ResolvedModel",
    "DownloadProgress",
    "ModelStatus",
    # errors
    "SDKException",
    "ErrorCode",
    "ErrorCategory",
    "is_sdk_exception",
    "as_sdk_exception",
    # events
    "EventBus",
    "bus",
    "RunAnywhereEvent",
    "InitializedEvent",
    "ServicesReadyEvent",
    "ShutdownEvent",
    "ModelLoadedEvent",
    "ModelUnloadedEvent",
    "GenerationEvent",
    # grammar / structured / tools
    "json_schema_to_grammar",
    "object_grammar",
    "parse_structured",
    "tool_call_schema",
    "tool_call_prompt",
    "ToolSpec",
    "ToolCall",
    "ToolRun",
    # streaming
    "stream_with_metrics",
    # audio helpers
    "float32_to_pcm16",
    "pcm16_to_float32",
    "pcm16_bytes",
    "downsample",
    "rms",
    "encode_wav",
    "decode_wav",
    # catalog
    "CATALOG",
    "CatalogEntry",
    "CatalogFile",
    "ModelType",
    "is_catalog_id",
    # download / resolution
    "resolve_model",
    "download_file",
    "models_root",
    "model_status",
]
