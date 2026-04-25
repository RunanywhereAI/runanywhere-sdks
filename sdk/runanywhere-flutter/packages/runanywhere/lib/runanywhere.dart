/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter.
library runanywhere;

// v3.1: voice-session legacy types DELETED (voice_session.dart,
// voice_session_handle.dart). Canonical voice-agent API is:
//   DartBridgeVoiceAgent.shared.initializeWithLoadedModels()
//   DartBridgeVoiceAgent.shared.getHandle()
//   VoiceAgentStreamAdapter(handle).stream() -> Stream<VoiceEvent>
export 'adapters/model_download_adapter.dart'
    show ModelDownloadService, ModelDownloadProgress, ModelDownloadStage;
export 'adapters/voice_agent_stream_adapter.dart' show VoiceAgentStreamAdapter;
export 'core/module/runanywhere_module.dart';
export 'core/types/component_state.dart';
export 'core/types/model_types.dart';
export 'core/types/npu_chip.dart';
export 'core/types/sdk_component.dart';
export 'core/types/storage_types.dart';
// Network layer
export 'data/network/network.dart';
export 'features/llm/llm_configuration.dart';
export 'features/stt/stt_configuration.dart';
export 'features/tts/tts_configuration.dart';
export 'features/vad/vad_configuration.dart';
export 'foundation/configuration/sdk_constants.dart';
export 'foundation/error_types/sdk_error.dart';
export 'foundation/logging/sdk_logger.dart';
export 'generated/voice_events.pb.dart'
    show VoiceEvent, StateChangeEvent, VADEvent, VoiceEvent_Payload;
export 'generated/voice_events.pbenum.dart'
    show PipelineState, VADEventType;
export 'native/dart_bridge_rag.dart' show DartBridgeRAG;
export 'native/dart_bridge_voice_agent.dart' show DartBridgeVoiceAgent;
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'native/platform_loader.dart' show PlatformLoader;
// v4.0: canonical instance API. Use RunAnywhereSDK.instance.{capability}.
export 'public/capabilities/runanywhere_downloads.dart'
    show RunAnywhereDownloads;
export 'public/capabilities/runanywhere_llm.dart' show RunAnywhereLLM;
export 'public/capabilities/runanywhere_models.dart' show RunAnywhereModels;
export 'public/capabilities/runanywhere_rag.dart' show RunAnywhereRAG;
export 'public/capabilities/runanywhere_stt.dart' show RunAnywhereSTT;
export 'public/capabilities/runanywhere_tools.dart' show RunAnywhereTools;
export 'public/capabilities/runanywhere_tts.dart' show RunAnywhereTTS;
export 'public/capabilities/runanywhere_vlm.dart' show RunAnywhereVLM;
export 'public/capabilities/runanywhere_voice.dart' show RunAnywhereVoice;
export 'public/configuration/sdk_environment.dart';
export 'public/errors/errors.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/extensions/rag_module.dart';
export 'public/extensions/runanywhere_device.dart';
export 'public/extensions/runanywhere_frameworks.dart';
export 'public/extensions/runanywhere_logging.dart';
export 'public/extensions/runanywhere_lora.dart';
export 'public/extensions/runanywhere_storage.dart';
export 'public/runanywhere_v4.dart' show RunAnywhereSDK;
export 'public/types/tool_calling_types.dart';
export 'public/types/types.dart' hide SupabaseConfig;
