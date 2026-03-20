/// Qualcomm Genie NPU backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via Qualcomm Genie NPU.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendGenie) handles all business logic:
/// - Service provider registration
/// - Model loading and inference on Snapdragon NPU
/// - Streaming generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_genie_register()` to register the backend
/// 2. The core SDK handles all LLM operations via `rac_llm_component_*`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere_genie/runanywhere_genie.dart';
///
/// // Register the module (matches Swift: Genie.register())
/// await Genie.register();
///
/// // Add models
/// Genie.addModel(
///   name: 'Qwen3 4B NPU',
///   url: 'https://huggingface.co/.../model.zip',
///   memoryRequirement: 4000000000,
/// );
/// ```
library runanywhere_genie;

import 'dart:async' show unawaited;

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/runanywhere.dart' show RunAnywhere;
import 'package:runanywhere_genie/native/genie_bindings.dart';

// Re-export for backward compatibility
export 'genie_error.dart';

/// Qualcomm Genie NPU module for LLM text generation.
///
/// Provides large language model capabilities using Qualcomm Genie
/// on Snapdragon NPU hardware.
///
/// Matches the Swift/Kotlin Genie module pattern.
class Genie implements RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches Swift enum pattern)
  // ============================================================================

  static final Genie _instance = Genie._internal();
  static Genie get module => _instance;
  Genie._internal();

  // ============================================================================
  // Module Info (matches Swift exactly)
  // ============================================================================

  /// Current version of the Genie Runtime module
  static const String version = '1.0.0';

  // ============================================================================
  // RunAnywhereModule Conformance (matches Swift exactly)
  // ============================================================================

  @override
  String get moduleId => 'genie';

  @override
  String get moduleName => 'Genie';

  @override
  Set<SDKComponent> get capabilities => {SDKComponent.llm};

  @override
  int get defaultPriority => 200;

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.genie;

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static GenieBindings? _bindings;
  static final _logger = SDKLogger('Genie');

  /// Internal model registry for models added via addModel
  static final List<ModelInfo> _registeredModels = [];

  // ============================================================================
  // Registration (matches Swift Genie.register() exactly)
  // ============================================================================

  /// Register Genie backend with the C++ service registry.
  ///
  /// This calls `rac_backend_genie_register()` to register the
  /// Genie service provider with the C++ commons layer.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  static Future<void> register({int priority = 200}) async {
    if (_isRegistered) {
      _logger.debug('Genie already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('Genie native library not available');
      return;
    }

    _logger.info('Registering Genie backend with C++ registry...');

    try {
      _bindings = GenieBindings();
      _logger.debug(
          'GenieBindings created, isAvailable: ${_bindings!.isAvailable}');

      final result = _bindings!.register();
      _logger.info(
          'rac_backend_genie_register() returned: $result (${RacResultCode.getMessage(result)})');

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.error('C++ backend registration FAILED with code: $result');
        return;
      }

      // No Dart-level provider needed - all LLM operations go through
      // DartBridgeLLM -> rac_llm_component_* (just like Swift CppBridge.LLM)

      _isRegistered = true;
      _logger.info('Genie LLM backend registered successfully');
    } catch (e) {
      _logger.error('GenieBindings not available: $e');
    }
  }

  /// Unregister the Genie backend from C++ registry.
  static void unregister() {
    if (_isRegistered) {
      _bindings?.unregister();
      _isRegistered = false;
      _logger.info('Genie LLM backend unregistered');
    }
  }

  // ============================================================================
  // Model Handling (matches Swift exactly)
  // ============================================================================

  /// Check if the native backend is available on this platform.
  ///
  /// Genie is Android/Snapdragon only:
  /// - On Android: Checks if librac_backend_genie_jni.so can be loaded
  /// - On iOS/other: Always returns false
  static bool get isAvailable => GenieBindings.checkAvailability();

  /// Check if Genie can handle a given model.
  /// Checks if the model ID contains "genie" or "npu" identifiers.
  static bool canHandle(String? modelId) {
    if (modelId == null) return false;
    final lowered = modelId.toLowerCase();
    return lowered.contains('genie') || lowered.contains('npu');
  }

  // ============================================================================
  // Model Registration (convenience API)
  // ============================================================================

  /// Add a LLM model to the registry.
  ///
  /// This is a convenience method that registers a model with the SDK.
  /// The model will be associated with the Genie NPU backend.
  ///
  /// Matches Swift pattern - models are registered globally via RunAnywhere.
  static void addModel({
    String? id,
    required String name,
    required String url,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _logger.error('Invalid URL for model: $name');
      return;
    }

    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    // Register with the global SDK registry (matches Swift pattern)
    final model = RunAnywhere.registerModel(
      id: modelId,
      name: name,
      url: uri,
      framework: InferenceFramework.genie,
      modality: ModelCategory.language,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    // Keep local reference for convenience
    _registeredModels.add(model);
    _logger.info('Added Genie model: $name ($modelId)');
  }

  /// Get all models registered with this module
  static List<ModelInfo> get registeredModels =>
      List.unmodifiable(_registeredModels);

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources
  static void dispose() {
    _bindings = null;
    _registeredModels.clear();
    _isRegistered = false;
    _logger.info('Genie disposed');
  }

  // ============================================================================
  // Auto-Registration (matches Swift exactly)
  // ============================================================================

  /// Enable auto-registration for this module.
  /// Call this method to trigger C++ backend registration.
  static void autoRegister() {
    unawaited(register());
  }
}
