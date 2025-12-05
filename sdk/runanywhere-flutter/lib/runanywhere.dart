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
export 'components/stt/stt_component.dart';
export 'components/llm/llm_component.dart';
export 'components/tts/tts_component.dart';
export 'components/vad/vad_component.dart';
export 'components/voice_agent/voice_agent_component.dart';
export 'capabilities/download/download_service.dart';
export 'capabilities/text_generation/generation_service.dart';
export 'capabilities/analytics/analytics_service.dart';

// Native FFI bindings for on-device AI capabilities
// Use: import 'package:runanywhere/native/native.dart';
// Or access via: NativeBackend, PlatformLoader, NativeProviderRegistration
export 'native/platform_loader.dart' show PlatformLoader;
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'native/native_provider_registration.dart' show NativeProviderRegistration;
