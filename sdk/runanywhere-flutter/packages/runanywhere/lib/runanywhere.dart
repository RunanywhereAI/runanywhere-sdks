/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter that brings powerful
/// AI models directly to your applications.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/runanywhere.dart';
///
/// // Initialize the SDK
/// await RunAnywhere.initialize();
///
/// // Register backends (from separate packages)
/// // import 'package:runanywhere_onnx/runanywhere_onnx.dart';
/// // import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
/// // await Onnx.register();
/// // await LlamaCpp.register();
/// ```
///
/// ## Architecture
///
/// The SDK is split into separate packages:
/// - `runanywhere` - Core SDK (this package)
/// - `runanywhere_onnx` - ONNX Runtime backend (STT, TTS, VAD, LLM)
/// - `runanywhere_llamacpp` - LlamaCpp backend (LLM)
///
/// Only include the backend packages you need in your app.
library runanywhere;

// Capability services
export 'capabilities/analytics/analytics_service.dart';
export 'capabilities/download/download_service.dart';
export 'capabilities/text_generation/generation_service.dart';

// Core types
export 'core/models/models.dart';
export 'core/module/module.dart';
export 'core/module_registry.dart' hide LLMGenerationOptions, TTSService;
export 'core/protocols/downloading/download_progress.dart';
export 'core/protocols/downloading/download_state.dart';
export 'core/protocols/downloading/download_task.dart';
export 'core/types/component_state.dart';
export 'core/types/sdk_component.dart';

// Feature capabilities
export 'features/llm/llm_capability.dart';
export 'features/stt/stt_capability.dart';
export 'features/tts/models/tts_options.dart' show TTSOptions;
export 'features/tts/tts_capability.dart';
export 'features/vad/vad_capability.dart';
export 'features/voice_agent/voice_agent_capability.dart';

// Native support (for backend packages)
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'native/platform_loader.dart' show PlatformLoader;

// Public API
export 'public/configuration/configuration.dart';
export 'public/errors/errors.dart';
export 'public/events/component_initialization_event.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/models/models.dart';
export 'public/runanywhere.dart';
