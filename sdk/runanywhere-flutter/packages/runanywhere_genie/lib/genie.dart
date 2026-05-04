/// Experimental Qualcomm Genie NPU backend shell for RunAnywhere Flutter SDK.
///
/// Functional LLM routing is Android/Snapdragon-only and requires native
/// binaries built with the Qualcomm Genie SDK. Without those binaries, the
/// backend remains unavailable and is not selected by the native router.
/// It is a **thin wrapper** around the native plugin shell. The module reports
/// LLM capability only after native registration succeeds.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend shell handles registration. Model loading, inference, and
/// streaming require a future SDK-backed implementation built with the
/// Qualcomm Genie SDK; the public shell returns backend-unavailable.
///
/// This Dart module just:
/// 1. Calls `rac_backend_genie_register()` to register the backend
/// 2. Lets the core SDK route LLM calls only if native registration succeeds
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

import 'dart:async';

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show InferenceFramework, ModelCategory;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/runanywhere_v4.dart' show RunAnywhereSDK;
import 'package:runanywhere_genie/native/genie_bindings.dart';

// Re-export for backward compatibility
export 'genie_error.dart';

/// Experimental Qualcomm Genie NPU module for LLM text generation.
///
/// Provides large language model capability only after SDK-backed native
/// registration succeeds on Android/Snapdragon hardware.
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
  Set<SDKComponent> get capabilities =>
      _isRegistered ? {SDKComponent.SDK_COMPONENT_LLM} : {};

  @override
  int get defaultPriority => _isRegistered ? 200 : 0;

  @override
  InferenceFramework get inferenceFramework =>
      InferenceFramework.INFERENCE_FRAMEWORK_GENIE;

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
  /// This calls `rac_backend_genie_register()` to register the Genie plugin
  /// with the C++ commons layer. SDK-absent shells are rejected by the native
  /// capability check and remain unavailable to the router.
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

      if (result == RacResultCode.errorBackendUnavailable ||
          result == RacResultCode.errorCapabilityUnsupported) {
        _logger.error(
            'Genie backend unavailable; Qualcomm Genie SDK-backed native ops are required.');
        return;
      }

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

  /// Check if the native backend library can be loaded on this platform.
  ///
  /// Genie is experimental and Android/Snapdragon only:
  /// - On Android: Checks only whether the native registration symbol exists.
  ///   Successful [register] is still required before this module advertises LLM.
  /// - On iOS/other: Always returns false
  static bool get isAvailable => GenieBindings.checkAvailability();

  /// Check if Genie can handle a given model.
  /// Checks if the model ID contains "genie" or "npu" identifiers.
  static bool canHandle(String? modelId) {
    if (!_isRegistered) return false;
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
  /// The model will be associated with the Genie NPU backend. Registration is
  /// only useful when [isAvailable] is true.
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
    final model = RunAnywhereSDK.instance.models.register(
      id: modelId,
      name: name,
      url: uri,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_GENIE,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
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
