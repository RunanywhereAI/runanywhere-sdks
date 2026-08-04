/// RunAnywhere Flutter SDK — core package.
///
/// `RunAnywhere` and its capability namespaces are the whole public surface.
/// Generated protobuf types remain the canonical data contract and are
/// re-exported below, minus the names the v3 API types shadow.
library;

export 'features/stt/services/audio_capture_manager.dart'
    show AudioCaptureManager;
export 'foundation/constants/sdk_constants.dart';
export 'foundation/errors/sdk_exception.dart';
export 'foundation/logging/sdk_logger.dart';
export 'public/api/namespaces/embeddings.dart'
    show EmbeddingsApi, RerankApi;
export 'public/api/namespaces/llm.dart' show LlmApi, ToolRunner, ToolsApi;
export 'public/api/namespaces/media.dart'
    show DiarizationApi, ImagesApi, SegmentationApi;
export 'public/api/namespaces/models.dart' show LoraApi, ModelsApi;
export 'public/api/namespaces/rag.dart' show RagApi, RagSession;
export 'public/api/namespaces/stt.dart' show SttApi;
export 'public/api/namespaces/tts.dart' show TtsApi;
export 'public/api/namespaces/vad.dart' show VadApi;
export 'public/api/namespaces/vlm.dart' show VlmApi;
export 'public/api/namespaces/voice.dart' show VoiceApi, VoiceSession;
export 'public/api/types/events.dart';
export 'public/api/types/inputs.dart';
export 'public/api/types/model_registration.dart';
export 'public/api/types/options.dart';
export 'public/api/types/results.dart';
export 'public/capabilities/runanywhere_cua.dart'
    show CuaAction, CuaActionKind, RunAnywhereCUA;
export 'public/capabilities/runanywhere_hybrid.dart' show RunAnywhereHybrid;
export 'public/capabilities/runanywhere_solutions.dart'
    show RunAnywhereSolutions;
export 'public/capabilities/runanywhere_tools.dart' show RunAnywhereTools;
export 'public/configuration/sdk_environment.dart';
export 'public/extensions/format_framework.dart' show formatFramework;
export 'public/extensions/model_category_extensions.dart'
    show ModelCategoryDefaults;
export 'public/hybrid/hybrid_cloud_backend.dart'
    show CloudBackend, cloudSttConfigJson;
export 'public/hybrid/hybrid_device_state.dart'
    show HybridDeviceState, HybridDeviceStateProvider;
export 'public/hybrid/hybrid_model.dart'
    show
        HybridBackend,
        HybridModel,
        HybridModelKind,
        kHybridDefaultCloudProvider;
export 'public/hybrid/hybrid_routing_policy.dart'
    show
        HybridBatteryFilter,
        HybridCascade,
        HybridConfidenceCascade,
        HybridCustomFilter,
        HybridFilter,
        HybridNetworkFilter,
        HybridQualityFilter,
        HybridRankOrder,
        HybridRoutingPolicy,
        kHybridSttConfidenceThreshold;
export 'public/hybrid/hybrid_stt_router.dart'
    show HybridSttRouter, HybridTranscribeException;
export 'public/runanywhere.dart' show RunAnywhere;
// Only the generated messages the public API actually hands back or takes in.
// Everything else stays behind a prefixed `runanywhere_protos.dart` import.
export 'runanywhere_protos.dart'
    show
        ArchiveStructure,
        ArchiveType,
        HybridRoutedMetadata,
        HybridSttTranscribeOptions,
        InferenceFramework,
        LoRAAdapterConfig,
        LoRAAdapterInfo,
        LoRAState,
        LoraAdapterCatalogEntry,
        LoraCompatibilityResult,
        MessageRole,
        ModelCategory,
        ModelFileDescriptor,
        ModelFormat,
        ModelInfo,
        ModelSource,
        RegisterModelFromUrlRequest,
        ThinkingTagPattern,
        ToolCall,
        ToolDefinition,
        ToolParameter,
        ToolParameterType,
        ToolResult,
        ToolValue;
