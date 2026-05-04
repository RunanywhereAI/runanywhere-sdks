/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter.
library runanywhere;

// Wave 2: Legacy hand-rolled types DELETED. The proto bindings are the
// canonical shape; throwables flow through SDKException directly.
export 'adapters/model_download_adapter.dart' show ModelDownloadService;
export 'adapters/voice_agent_stream_adapter.dart' show VoiceAgentStreamAdapter;
export 'core/module/runanywhere_module.dart';
export 'core/types/model_types.dart'
    hide
        ArchiveArtifact,
        ArchiveStructure,
        ArchiveType,
        BuiltInArtifact,
        CustomArtifact,
        ExpectedModelFiles,
        InferenceFramework,
        ModelArtifactType,
        ModelCategory,
        ModelFileDescriptor,
        ModelFormat,
        ModelInfo,
        ModelSource,
        MultiFileArtifact,
        SingleFileArtifact,
        ThinkingTagPattern;
export 'core/types/npu_chip.dart';
export 'core/types/sdk_component.dart' hide SDKComponent;
export 'data/network/network.dart';
export 'foundation/configuration/sdk_constants.dart';
export 'foundation/error_types/sdk_exception.dart';
export 'foundation/logging/sdk_logger.dart';
export 'generated/diffusion_options.pb.dart'
    show
        DiffusionCapabilities,
        DiffusionConfig,
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionProgress,
        DiffusionResult,
        DiffusionTokenizerSource;
export 'generated/diffusion_options.pbenum.dart'
    show
        DiffusionMode,
        DiffusionModelVariant,
        DiffusionScheduler,
        DiffusionTokenizerSourceKind;
export 'generated/download_service.pb.dart'
    show
        DownloadCancelRequest,
        DownloadCancelResult,
        DownloadPlanRequest,
        DownloadPlanResult,
        DownloadProgress,
        DownloadResumeRequest,
        DownloadResumeResult,
        DownloadStartRequest,
        DownloadStartResult,
        DownloadSubscribeRequest;
export 'generated/download_service.pbenum.dart'
    show DownloadStage, DownloadState;
export 'generated/embeddings_options.pb.dart'
    show
        EmbeddingsConfiguration,
        EmbeddingsOptions,
        EmbeddingsRequest,
        EmbeddingsResult;
export 'generated/embeddings_options.pbenum.dart'
    show EmbeddingsNormalizeMode, EmbeddingsPoolingStrategy;
export 'generated/errors.pb.dart' show ErrorContext;
export 'generated/errors.pbenum.dart' show ErrorCategory, ErrorCode;
export 'generated/hardware_profile.pb.dart'
    show AcceleratorInfo, HardwareProfile, HardwareProfileResult;
export 'generated/hardware_profile.pbenum.dart' show AcceleratorPreference;
export 'generated/llm_options.pb.dart'
    show LLMConfiguration, LLMGenerationOptions, LLMGenerationResult;
export 'generated/llm_options.pbenum.dart' show ExecutionTarget;
export 'generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent, LLMStreamFinalResult;
export 'generated/lora_options.pb.dart'
    show
        LoRAAdapterConfig,
        LoRAAdapterInfo,
        LoraAdapterCatalogEntry,
        LoraCompatibilityResult;
export 'generated/model_types.pb.dart'
    show
        ArchiveArtifact,
        CurrentModelRequest,
        CurrentModelResult,
        ExpectedModelFiles,
        ModelFileDescriptor,
        ModelInfo,
        MultiFileArtifact,
        ModelInfoList,
        ModelLoadRequest,
        ModelLoadResult,
        ModelListRequest,
        ModelListResult,
        ModelQuery,
        ModelUnloadRequest,
        ModelUnloadResult,
        SingleFileArtifact;
export 'generated/model_types.pbenum.dart'
    show
        AccelerationPreference,
        ArchiveStructure,
        ArchiveType,
        AudioFormat,
        InferenceFramework,
        ModelArtifactType,
        ModelCategory,
        ModelFormat,
        ModelSource,
        ModelQuerySortField,
        ModelQuerySortOrder,
        RoutingPolicy;
export 'generated/rag.pb.dart'
    show
        RAGConfiguration,
        RAGDocument,
        RAGQueryOptions,
        RAGResult,
        RAGSearchResult,
        RAGStatistics;
export 'generated/sdk_events.pb.dart'
    show
        ComponentLifecycleSnapshot,
        ComponentInitializationEvent,
        ConfigurationEvent,
        DeviceEvent,
        FrameworkEvent,
        GenerationEvent,
        InitializationEvent,
        ModelEvent,
        NetworkEvent,
        PerformanceEvent,
        SDKEvent,
        StorageEvent,
        VoiceLifecycleEvent;
export 'generated/sdk_events.pbenum.dart'
    show
        ComponentLifecycleState,
        ComponentInitializationEventKind,
        ConfigurationEventKind,
        DeviceEventKind,
        EventDestination,
        EventSeverity,
        FrameworkEventKind,
        GenerationEventKind,
        InitializationStage,
        ModelEventKind,
        NetworkEventKind,
        PerformanceEventKind,
        SDKComponent,
        StorageEventKind,
        VoiceEventKind;
export 'generated/storage_types.pb.dart'
    show
        AppStorageInfo,
        DeviceStorageInfo,
        ModelStorageMetrics,
        StorageAvailability,
        StorageAvailabilityRequest,
        StorageAvailabilityResult,
        StorageDeletePlan,
        StorageDeletePlanRequest,
        StorageDeleteRequest,
        StorageDeleteResult,
        StorageInfo,
        StorageInfoRequest,
        StorageInfoResult,
        StoredModel;
export 'generated/structured_output.pb.dart'
    show
        JSONSchema,
        StructuredOutputOptions,
        StructuredOutputResult,
        StructuredOutputValidation;
export 'generated/stt_options.pb.dart'
    show
        STTConfiguration,
        STTOptions,
        STTOutput,
        STTPartialResult,
        TranscriptionAlternative,
        TranscriptionMetadata,
        WordTimestamp;
export 'generated/stt_options.pbenum.dart' show STTLanguage;
export 'generated/stt_options_helpers.dart';
export 'generated/tool_calling.pb.dart'
    show
        ToolCall,
        ToolCallingOptions,
        ToolCallingResult,
        ToolDefinition,
        ToolParameter,
        ToolResult;
export 'generated/tool_calling.pbenum.dart'
    show ToolCallFormatName, ToolParameterType;
export 'generated/tts_options.pb.dart'
    show
        TTSConfiguration,
        TTSOptions,
        TTSOutput,
        TTSPhonemeTimestamp,
        TTSSpeakResult,
        TTSSynthesisMetadata,
        TTSVoiceInfo;
export 'generated/vad_options.pb.dart'
    show VADConfiguration, VADOptions, VADResult, VADStatistics;
export 'generated/vlm_options.pb.dart'
    show
        VLMChatTemplate,
        VLMConfiguration,
        VLMGenerationOptions,
        VLMImage,
        VLMResult;
export 'generated/vlm_options.pbenum.dart'
    show VLMErrorCode, VLMImageFormat, VLMModelFamily;
export 'generated/voice_agent_service.pb.dart'
    show
        VoiceAgentComposeConfig,
        VoiceAgentRequest,
        VoiceAgentResult,
        VoiceSessionConfig;
export 'generated/voice_events.pb.dart'
    show
        StateChangeEvent,
        VADEvent,
        VoiceAgentComponentStates,
        VoiceEvent,
        VoiceEvent_Payload,
        VoiceSessionError;
export 'generated/voice_events.pbenum.dart'
    show ComponentLoadState, PipelineState, VADEventType, VoiceSessionErrorCode;
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'public/capabilities/runanywhere_diffusion.dart'
    show RunAnywhereDiffusion;
export 'public/capabilities/runanywhere_downloads.dart'
    show RunAnywhereDownloads;
export 'public/capabilities/runanywhere_embeddings.dart'
    show RunAnywhereEmbeddings;
export 'public/capabilities/runanywhere_hardware.dart' show RunAnywhereHardware;
export 'public/capabilities/runanywhere_llm.dart' show RunAnywhereLLM;
export 'public/capabilities/runanywhere_lora.dart'
    show RunAnywhereLoRACapability;
export 'public/capabilities/runanywhere_model_lifecycle.dart'
    show RunAnywhereModelLifecycle;
export 'public/capabilities/runanywhere_models.dart' show RunAnywhereModels;
export 'public/capabilities/runanywhere_plugin_loader.dart'
    show PluginInfo, RunAnywherePluginLoaderCapability;
export 'public/capabilities/runanywhere_rag.dart' show RunAnywhereRAG;
export 'public/capabilities/runanywhere_stt.dart' show RunAnywhereSTT;
export 'public/capabilities/runanywhere_tools.dart'
    show RunAnywhereTools, ToolCallFormatNames, ToolExecutor;
export 'public/capabilities/runanywhere_tts.dart' show RunAnywhereTTS;
export 'public/capabilities/runanywhere_vad.dart' show RunAnywhereVAD;
export 'public/capabilities/runanywhere_vlm.dart' show RunAnywhereVLM;
export 'public/capabilities/runanywhere_vlm_models.dart'
    show RunAnywhereVLMModels;
export 'public/capabilities/runanywhere_voice.dart'
    show RunAnywhereVoice, VoiceAgentConfiguration;
export 'public/capabilities/runanywhere_voice_agent.dart'
    show RunAnywhereVoiceAgent;
export 'public/configuration/sdk_environment.dart';
export 'public/extensions/rag_module.dart';
export 'public/extensions/runanywhere_flat_aliases.dart';
export 'public/extensions/runanywhere_frameworks.dart';
export 'public/extensions/runanywhere_logging.dart';
export 'public/extensions/runanywhere_lora.dart';
export 'public/extensions/runanywhere_model_assignments.dart'
    show RunAnywhereModelAssignments;
export 'public/extensions/runanywhere_model_management.dart'
    show RunAnywhereModelManagement;
export 'public/extensions/runanywhere_storage.dart';
export 'public/extensions/runanywhere_structured_output.dart'
    show RunAnywhereStructuredOutput;
export 'public/extensions/runanywhere_thinking_utils.dart'
    show RunAnywhereThinkingUtils, ThinkingExtractionResult;
export 'public/runanywhere_v4.dart' show RunAnywhereSDK;
export 'public/types/types.dart';
