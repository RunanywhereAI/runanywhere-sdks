/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter.
library runanywhere;

// v3.1: voice-session legacy types DELETED (voice_session.dart,
// voice_session_handle.dart). Canonical voice-agent API is:
//   DartBridgeVoiceAgent.shared.initializeWithLoadedModels()
//   DartBridgeVoiceAgent.shared.getHandle()
//   VoiceAgentStreamAdapter(handle).stream() -> Stream<VoiceEvent>
export 'adapters/voice_agent_stream_adapter.dart' show VoiceAgentStreamAdapter;
export 'generated/voice_events.pb.dart' show VoiceEvent, StateChangeEvent, VADEvent, VoiceEvent_Payload;
export 'native/dart_bridge_voice_agent.dart' show DartBridgeVoiceAgent;
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
export 'infrastructure/download/download_service.dart'
    show ModelDownloadService, ModelDownloadProgress, ModelDownloadStage;
export 'native/dart_bridge_rag.dart' show DartBridgeRAG;
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'native/platform_loader.dart' show PlatformLoader;
export 'public/configuration/sdk_environment.dart';
export 'public/errors/errors.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/extensions/runanywhere_device.dart';
export 'public/extensions/runanywhere_frameworks.dart';
export 'public/extensions/runanywhere_logging.dart';
export 'public/extensions/runanywhere_lora.dart';
export 'public/extensions/runanywhere_storage.dart';
export 'public/runanywhere.dart';
export 'public/runanywhere_tool_calling.dart';
export 'public/types/tool_calling_types.dart';
export 'public/types/types.dart' hide SupabaseConfig;
