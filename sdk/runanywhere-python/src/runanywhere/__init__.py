"""RunAnywhere Python SDK.

This package re-exports the protobuf-generated message and enum classes
under the top-level ``runanywhere`` namespace so consumers can write::

    from runanywhere import STTOptions, TTSOptions, SDKError

Re-exports come from ``runanywhere.generated.*_pb2`` modules. The full
protobuf modules remain accessible via ``runanywhere.generated`` for
advanced use cases (descriptors, FileDescriptor access, etc.).
"""

# STT (Speech-to-Text)
from runanywhere.generated.stt_options_pb2 import (
    STTConfiguration,
    STTLanguage,
    STTOptions,
    STTOutput,
    STTPartialResult,
    TranscriptionAlternative,
    TranscriptionMetadata,
    WordTimestamp,
)

# TTS (Text-to-Speech)
from runanywhere.generated.tts_options_pb2 import (
    TTSConfiguration,
    TTSOptions,
    TTSOutput,
    TTSPhonemeTimestamp,
    TTSSpeakResult,
    TTSSynthesisMetadata,
    TTSVoiceGender,
    TTSVoiceInfo,
)

# VAD (Voice Activity Detection)
from runanywhere.generated.vad_options_pb2 import (
    SpeechActivityEvent,
    SpeechActivityKind,
    VADConfiguration,
    VADOptions,
    VADResult,
    VADStatistics,
)

# VLM (Vision-Language Models)
from runanywhere.generated.vlm_options_pb2 import (
    VLMConfiguration,
    VLMErrorCode,
    VLMGenerationOptions,
    VLMImage,
    VLMImageFormat,
    VLMResult,
)

# Diffusion (image generation)
from runanywhere.generated.diffusion_options_pb2 import (
    DiffusionCapabilities,
    DiffusionConfiguration,
    DiffusionGenerationOptions,
    DiffusionMode,
    DiffusionModelVariant,
    DiffusionProgress,
    DiffusionResult,
    DiffusionScheduler,
    DiffusionTokenizerSource,
    DiffusionTokenizerSourceKind,
)

# LoRA adapters
from runanywhere.generated.lora_options_pb2 import (
    LoRAAdapterConfig,
    LoRAAdapterInfo,
    LoraAdapterCatalogEntry,
    LoraCompatibilityResult,
)

# RAG (Retrieval-Augmented Generation)
from runanywhere.generated.rag_pb2 import (
    RAGConfiguration,
    RAGQueryOptions,
    RAGResult,
    RAGSearchResult,
    RAGStatistics,
)

# Embeddings
from runanywhere.generated.embeddings_options_pb2 import (
    EmbeddingsConfiguration,
    EmbeddingsOptions,
    EmbeddingsResult,
    EmbeddingVector,
)

# Storage types
from runanywhere.generated.storage_types_pb2 import (
    AppStorageInfo,
    DeviceStorageInfo,
    ModelStorageMetrics,
    NPUChip,
    StorageAvailability,
    StorageInfo,
    StoredModel,
)

# Errors
from runanywhere.generated.errors_pb2 import (
    ErrorCategory,
    ErrorCode,
    ErrorContext,
    SDKError,
)

# SDK events
from runanywhere.generated.sdk_events_pb2 import (
    ComponentInitializationEvent,
    ComponentInitializationEventKind,
    ConfigurationEvent,
    ConfigurationEventKind,
    DeviceEvent,
    DeviceEventKind,
    EventDestination,
    EventSeverity,
    FrameworkEvent,
    FrameworkEventKind,
    GenerationEvent,
    GenerationEventKind,
    InitializationEvent,
    InitializationStage,
    ModelEvent,
    ModelEventKind,
    NetworkEvent,
    NetworkEventKind,
    PerformanceEvent,
    PerformanceEventKind,
    SDKComponent,
    SDKEvent,
    StorageEvent,
    StorageEventKind,
    VoiceEventKind,
    VoiceLifecycleEvent,
)

# Structured output
from runanywhere.generated.structured_output_pb2 import (
    ClassificationCandidate,
    ClassificationResult,
    EntityExtractionResult,
    JSONSchema,
    JSONSchemaProperty,
    JSONSchemaType,
    NamedEntity,
    NERResult,
    Sentiment,
    SentimentResult,
    StructuredOutputOptions,
    StructuredOutputResult,
    StructuredOutputValidation,
)

__all__ = [
    # STT
    "STTConfiguration",
    "STTLanguage",
    "STTOptions",
    "STTOutput",
    "STTPartialResult",
    "TranscriptionAlternative",
    "TranscriptionMetadata",
    "WordTimestamp",
    # TTS
    "TTSConfiguration",
    "TTSOptions",
    "TTSOutput",
    "TTSPhonemeTimestamp",
    "TTSSpeakResult",
    "TTSSynthesisMetadata",
    "TTSVoiceGender",
    "TTSVoiceInfo",
    # VAD
    "SpeechActivityEvent",
    "SpeechActivityKind",
    "VADConfiguration",
    "VADOptions",
    "VADResult",
    "VADStatistics",
    # VLM
    "VLMConfiguration",
    "VLMErrorCode",
    "VLMGenerationOptions",
    "VLMImage",
    "VLMImageFormat",
    "VLMResult",
    # Diffusion
    "DiffusionCapabilities",
    "DiffusionConfiguration",
    "DiffusionGenerationOptions",
    "DiffusionMode",
    "DiffusionModelVariant",
    "DiffusionProgress",
    "DiffusionResult",
    "DiffusionScheduler",
    "DiffusionTokenizerSource",
    "DiffusionTokenizerSourceKind",
    # LoRA
    "LoRAAdapterConfig",
    "LoRAAdapterInfo",
    "LoraAdapterCatalogEntry",
    "LoraCompatibilityResult",
    # RAG
    "RAGConfiguration",
    "RAGQueryOptions",
    "RAGResult",
    "RAGSearchResult",
    "RAGStatistics",
    # Embeddings
    "EmbeddingsConfiguration",
    "EmbeddingsOptions",
    "EmbeddingsResult",
    "EmbeddingVector",
    # Storage
    "AppStorageInfo",
    "DeviceStorageInfo",
    "ModelStorageMetrics",
    "NPUChip",
    "StorageAvailability",
    "StorageInfo",
    "StoredModel",
    # Errors
    "ErrorCategory",
    "ErrorCode",
    "ErrorContext",
    "SDKError",
    # SDK events
    "ComponentInitializationEvent",
    "ComponentInitializationEventKind",
    "ConfigurationEvent",
    "ConfigurationEventKind",
    "DeviceEvent",
    "DeviceEventKind",
    "EventDestination",
    "EventSeverity",
    "FrameworkEvent",
    "FrameworkEventKind",
    "GenerationEvent",
    "GenerationEventKind",
    "InitializationEvent",
    "InitializationStage",
    "ModelEvent",
    "ModelEventKind",
    "NetworkEvent",
    "NetworkEventKind",
    "PerformanceEvent",
    "PerformanceEventKind",
    "SDKComponent",
    "SDKEvent",
    "StorageEvent",
    "StorageEventKind",
    "VoiceEventKind",
    "VoiceLifecycleEvent",
    # Structured output
    "ClassificationCandidate",
    "ClassificationResult",
    "EntityExtractionResult",
    "JSONSchema",
    "JSONSchemaProperty",
    "JSONSchemaType",
    "NamedEntity",
    "NERResult",
    "Sentiment",
    "SentimentResult",
    "StructuredOutputOptions",
    "StructuredOutputResult",
    "StructuredOutputValidation",
]
