/// RunAnywhere Flutter SDK - Core Package
///
/// Privacy-first, on-device AI SDK for Flutter.
library runanywhere;

// Core types
export 'core/types/model_types.dart';
export 'core/types/storage_types.dart';
export 'core/types/component_state.dart';
export 'core/types/sdk_component.dart';

// Framework types
export 'core/models/framework/llm_framework.dart';
export 'core/models/framework/framework_modality.dart';
export 'core/models/model/model_registration.dart';

// Module system
export 'core/module/runanywhere_module.dart';
export 'core/module_registry.dart'
    hide LLMGenerationOptions, LLMGenerationResult;

// Native support (for backend packages)
export 'native/native_backend.dart' show NativeBackend, NativeBackendException;
export 'native/platform_loader.dart' show PlatformLoader;

// VAD configuration
export 'features/vad/vad_configuration.dart';

// Voice session (for voice assistant)
export 'capabilities/voice/models/voice_session.dart';
export 'capabilities/voice/models/voice_session_handle.dart';

// Foundation
export 'foundation/configuration/sdk_constants.dart';
export 'foundation/error_types/sdk_error.dart';
export 'foundation/logging/sdk_logger.dart';

// Infrastructure (download service)
export 'infrastructure/download/download_service.dart'
    show ModelDownloadService, ModelDownloadProgress, ModelDownloadStage;

// Public API
export 'public/configuration/sdk_environment.dart';
export 'public/errors/errors.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/runanywhere.dart' hide SupabaseConfig;
