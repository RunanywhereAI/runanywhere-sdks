/// RunAnywhere Flutter SDK
///
/// Privacy-first, on-device AI SDK for Flutter that brings powerful language
/// models directly to your applications.
library runanywhere;

export 'capabilities/analytics/analytics_service.dart';
export 'capabilities/download/download_service.dart';
export 'capabilities/text_generation/generation_service.dart';
export 'core/module_registry.dart'
    hide LLMGenerationOptions, TTSService;
export 'core/protocols/downloading/download_progress.dart';
export 'core/protocols/downloading/download_state.dart';
// Download types for model downloading
export 'core/protocols/downloading/download_task.dart';
export 'core/types/component_state.dart';
export 'core/types/sdk_component.dart';
export 'features/llm/llm_capability.dart';
export 'features/stt/stt_capability.dart';
export 'features/tts/models/tts_options.dart' show TTSOptions;
export 'features/tts/tts_capability.dart';
export 'features/vad/vad_capability.dart';
export 'features/voice_agent/voice_agent_capability.dart';
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
// Native FFI bindings for on-device AI capabilities
// Access via: NativeBackend, PlatformLoader
export 'native/platform_loader.dart' show PlatformLoader;
export 'public/configuration/configuration.dart';
export 'public/errors/errors.dart';
export 'public/events/component_initialization_event.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/models/models.dart';
export 'public/runanywhere.dart';

// Backend modules (modular architecture - import specific backends as needed)
// Use: import 'package:runanywhere/backends/onnx/onnx.dart';
// Or for all: import 'package:runanywhere/backends/backends.dart';
// See ARCHITECTURE.md for details on the modular backend system.
