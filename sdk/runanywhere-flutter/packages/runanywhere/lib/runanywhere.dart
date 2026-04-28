/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter.
library runanywhere;

// Wave 2: Legacy hand-rolled types DELETED. The proto bindings are the
// canonical shape; throwables flow through SDKException directly.
export 'adapters/model_download_adapter.dart'
    show ModelDownloadService, ModelDownloadProgress, ModelDownloadStage;
export 'adapters/voice_agent_stream_adapter.dart' show VoiceAgentStreamAdapter;
export 'core/module/runanywhere_module.dart';
export 'core/types/component_state.dart';
export 'core/types/model_types.dart';
export 'core/types/npu_chip.dart';
export 'core/types/sdk_component.dart';
// Network layer
export 'data/network/network.dart';
export 'foundation/configuration/sdk_constants.dart';
export 'foundation/error_types/sdk_exception.dart';
export 'foundation/logging/sdk_logger.dart';
// Proto-generated public types (Wave 2: canonical types).
export 'generated/errors.pb.dart' show ErrorContext;
export 'generated/errors.pbenum.dart' show ErrorCategory, ErrorCode;
export 'generated/llm_options.pb.dart'
    show LLMConfiguration, LLMGenerationOptions, LLMGenerationResult;
export 'generated/llm_options.pbenum.dart' show ExecutionTarget;
export 'generated/llm_service.pb.dart' show LLMStreamEvent;
export 'generated/lora_options.pb.dart'
    show
        LoRAAdapterConfig,
        LoRAAdapterInfo,
        LoraAdapterCatalogEntry,
        LoraCompatibilityResult;
export 'generated/rag.pb.dart'
    show
        RAGConfiguration,
        RAGQueryOptions,
        RAGSearchResult,
        RAGResult,
        RAGStatistics;
export 'generated/storage_types.pb.dart'
    show
        DeviceStorageInfo,
        AppStorageInfo,
        ModelStorageMetrics,
        StoredModel,
        StorageInfo,
        StorageAvailability;
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
export 'generated/structured_output.pb.dart'
    show StructuredOutputOptions, StructuredOutputResult, StructuredOutputValidation;
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
    show VLMGenerationOptions, VLMImage, VLMResult;
export 'generated/voice_events.pb.dart'
    show VoiceEvent, StateChangeEvent, VADEvent, VoiceEvent_Payload;
export 'generated/voice_events.pbenum.dart'
    show PipelineState, VADEventType;
// FFI bridges and platform loader are SDK-internal — consumers reach
// the high-level capability classes via `RunAnywhereSDK.instance.*`.
// `NativeBackend` / `NativeBackendException` are kept exposed because
// sub-packages (runanywhere_llamacpp, _onnx, _genie) implement and
// register backends through them.
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
// v4.0: canonical instance API. Use RunAnywhereSDK.instance.{capability}.
export 'public/capabilities/runanywhere_diffusion.dart'
    show RunAnywhereDiffusion;
export 'public/capabilities/runanywhere_downloads.dart'
    show RunAnywhereDownloads;
export 'public/capabilities/runanywhere_llm.dart' show RunAnywhereLLM;
export 'public/capabilities/runanywhere_models.dart' show RunAnywhereModels;
export 'public/capabilities/runanywhere_rag.dart' show RunAnywhereRAG;
export 'public/capabilities/runanywhere_stt.dart' show RunAnywhereSTT;
export 'public/capabilities/runanywhere_tools.dart' show RunAnywhereTools;
export 'public/capabilities/runanywhere_tts.dart' show RunAnywhereTTS;
export 'public/capabilities/runanywhere_vad.dart'
    show RunAnywhereVAD, SpeechActivityEvent;
export 'public/capabilities/runanywhere_vlm.dart' show RunAnywhereVLM;
// runanywhere_vision_language.dart is the canonical VisionLanguage namespace
// file; RunAnywhereVLM is already exported above via runanywhere_vlm.dart.
export 'public/capabilities/runanywhere_vlm_models.dart'
    show RunAnywhereVLMModels;
export 'public/capabilities/runanywhere_voice.dart'
    show RunAnywhereVoice, VoiceAgentConfiguration, VoiceAgentResult;
export 'public/capabilities/runanywhere_voice_agent.dart'
    show RunAnywhereVoiceAgent;
export 'public/configuration/sdk_environment.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/extensions/rag_module.dart';
export 'public/extensions/runanywhere_device.dart';
export 'public/extensions/runanywhere_frameworks.dart';
export 'public/extensions/runanywhere_logging.dart';
export 'public/extensions/runanywhere_lora.dart';
export 'public/extensions/runanywhere_model_assignments.dart'
    show RunAnywhereModelAssignments;
export 'public/extensions/runanywhere_model_management.dart'
    show RunAnywhereModelManagement;
export 'public/extensions/runanywhere_plugin_loader.dart'
    show RunAnywherePluginLoader;
export 'public/extensions/runanywhere_storage.dart';
export 'public/extensions/runanywhere_structured_output.dart'
    show RunAnywhereStructuredOutput;
export 'public/runanywhere_v4.dart' show RunAnywhereSDK;
export 'public/types/tool_calling_types.dart';
export 'public/types/types.dart';
