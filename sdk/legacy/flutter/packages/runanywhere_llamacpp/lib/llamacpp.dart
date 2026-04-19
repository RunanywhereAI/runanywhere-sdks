/// LlamaCPP backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendLlamaCPP) handles all business logic:
/// - Service provider registration
/// - Model loading and inference
/// - Streaming generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_llamacpp_register()` to register the backend
/// 2. The core SDK handles all LLM operations via `rac_llm_component_*`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
///
/// // Register the module (matches Swift: LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Add models
/// LlamaCpp.addModel(
///   name: 'SmolLM2 360M Q8_0',
///   url: 'https://huggingface.co/.../model.gguf',
///   memoryRequirement: 500000000,
/// );
/// ```
library runanywhere_llamacpp;

import 'dart:async' show unawaited;

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/runanywhere.dart' show RunAnywhere;
import 'package:runanywhere_llamacpp/native/llamacpp_bindings.dart';

// Re-export for backward compatibility
export 'llamacpp_error.dart';

/// LlamaCPP module for LLM text generation.
///
/// Provides large language model capabilities using llama.cpp
/// with GGUF models and Metal/GPU acceleration.
///
/// Matches Swift `LlamaCPP` enum from LlamaCPPRuntime/LlamaCPP.swift.
class LlamaCpp implements RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches Swift enum pattern)
  // ============================================================================

  static final LlamaCpp _instance = LlamaCpp._internal();
  static LlamaCpp get module => _instance;
  LlamaCpp._internal();

  // ============================================================================
  // Module Info (matches Swift exactly)
  // ============================================================================

  /// Current version of the LlamaCPP Runtime module
  static const String version = '2.0.0';

  /// LlamaCPP library version (underlying C++ library)
  static const String llamaCppVersion = 'b7199';

  // ============================================================================
  // RunAnywhereModule Conformance (matches Swift exactly)
  // ============================================================================

  @override
  String get moduleId => 'llamacpp';

  @override
  String get moduleName => 'LlamaCPP';

  @override
  Set<SDKComponent> get capabilities => {SDKComponent.llm, SDKComponent.vlm};

  @override
  int get defaultPriority => 100;

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.llamaCpp;

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static bool _isVlmRegistered = false;
  static LlamaCppBindings? _bindings;
  static final _logger = SDKLogger('LlamaCpp');

  /// Internal model registry for models added via addModel
  static final List<ModelInfo> _registeredModels = [];

  // ============================================================================
  // Registration (matches Swift LlamaCPP.register() exactly)
  // ============================================================================

  /// Register LlamaCPP backend with the C++ service registry.
  ///
  /// This calls `rac_backend_llamacpp_register()` to register the
  /// LlamaCPP service provider with the C++ commons layer.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  static Future<void> register({int priority = 100}) async {
    if (_isRegistered) {
      _logger.debug('LlamaCpp already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('LlamaCpp native library not available');
      return;
    }

    _logger.info('Registering LlamaCpp backend with C++ registry...');

    try {
      _bindings = LlamaCppBindings();
      _logger.debug(
          'LlamaCppBindings created, isAvailable: ${_bindings!.isAvailable}');

      final result = _bindings!.register();
      _logger.info(
          'rac_backend_llamacpp_register() returned: $result (${RacResultCode.getMessage(result)})');

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.error('C++ backend registration FAILED with code: $result');
        return;
      }

      // No Dart-level provider needed - all LLM operations go through
      // DartBridgeLLM -> rac_llm_component_* (just like Swift CppBridge.LLM)

      _isRegistered = true;
      _logger.info('LlamaCpp LLM backend registered successfully');

      // Register VLM backend (Vision Language Model)
      _registerVlm();
    } catch (e) {
      _logger.error('LlamaCppBindings not available: $e');
    }
  }

  /// Register VLM (Vision Language Model) backend.
  ///
  /// This is called automatically by register() - matches iOS pattern.
  static void _registerVlm() {
    if (_isVlmRegistered) {
      _logger.debug('LlamaCpp VLM already registered');
      return;
    }

    if (_bindings == null) {
      _logger.warning('Cannot register VLM: bindings not available');
      return;
    }

    _logger.info('Registering LlamaCpp VLM backend...');

    try {
      final vlmResult = _bindings!.registerVlm();
      _logger.info(
          'rac_backend_llamacpp_vlm_register() returned: $vlmResult (${RacResultCode.getMessage(vlmResult)})');

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (vlmResult != RacResultCode.success &&
          vlmResult != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.warning(
            'C++ VLM backend registration failed with code: $vlmResult (VLM features may not be available)');
        return;
      }

      _isVlmRegistered = true;
      _logger.info('LlamaCpp VLM backend registered successfully');
    } catch (e) {
      _logger.warning('VLM registration failed: $e (VLM features may not be available)');
    }
  }

  /// Unregister the LlamaCPP backend from C++ registry.
  static void unregister() {
    if (_isVlmRegistered) {
      _bindings?.unregisterVlm();
      _isVlmRegistered = false;
      _logger.info('LlamaCpp VLM backend unregistered');
    }

    if (_isRegistered) {
      _bindings?.unregister();
      _isRegistered = false;
      _logger.info('LlamaCpp LLM backend unregistered');
    }
  }

  // ============================================================================
  // Model Handling (matches Swift exactly)
  // ============================================================================

  /// Check if the native backend is available on this platform.
  ///
  /// On iOS: Checks DynamicLibrary.process() for statically linked symbols
  /// On Android: Checks if librac_backend_llamacpp_jni.so can be loaded
  static bool get isAvailable => LlamaCppBindings.checkAvailability();

  /// Check if LlamaCPP can handle a given model.
  /// Uses file extension pattern matching - actual framework info is in C++ registry.
  static bool canHandle(String? modelId) {
    if (modelId == null) return false;
    return modelId.toLowerCase().endsWith('.gguf');
  }

  // ============================================================================
  // Model Registration (convenience API)
  // ============================================================================

  /// Add a LLM model to the registry.
  ///
  /// This is a convenience method that registers a model with the SDK.
  /// The model will be associated with the LlamaCPP backend.
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
      framework: InferenceFramework.llamaCpp,
      modality: ModelCategory.language,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    // Keep local reference for convenience
    _registeredModels.add(model);
    _logger.info('Added LlamaCpp model: $name ($modelId)');
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
    _logger.info('LlamaCpp disposed');
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
