/// RunAnywhere Flutter SDK
///
/// Privacy-first, on-device AI SDK for Flutter that brings powerful language
/// models directly to your applications.
library runanywhere;

export 'public/runanywhere.dart';
export 'public/models/models.dart';
export 'public/errors/errors.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/events/component_initialization_event.dart';
export 'public/configuration/configuration.dart';
export 'core/types/component_state.dart';
export 'core/types/sdk_component.dart';
export 'core/module_registry.dart' hide LLMGenerationOptions;
export 'features/stt/stt_capability.dart';
export 'features/llm/llm_capability.dart';
export 'features/tts/tts_capability.dart';
export 'features/vad/vad_capability.dart';
export 'features/voice_agent/voice_agent_capability.dart';
export 'capabilities/download/download_service.dart';
export 'capabilities/text_generation/generation_service.dart';
export 'capabilities/analytics/analytics_service.dart';

// Download types for model downloading
export 'core/protocols/downloading/download_task.dart';
export 'core/protocols/downloading/download_progress.dart';
export 'core/protocols/downloading/download_state.dart';

// Native FFI bindings for on-device AI capabilities
// Access via: NativeBackend, PlatformLoader
export 'backends/native/platform_loader.dart' show PlatformLoader;
export 'backends/native/native_backend.dart'
    show NativeBackend, NativeBackendException;

// Backend modules (modular architecture - import specific backends as needed)
// Use: import 'package:runanywhere/backends/onnx/onnx.dart';
// Or for all: import 'package:runanywhere/backends/backends.dart';
// See ARCHITECTURE.md for details on the modular backend system.
