/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, and VAD capabilities via ONNX Runtime.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendONNX) handles all business logic:
/// - Service provider registration
/// - Model loading and inference for STT/TTS/VAD
/// - Streaming transcription
///
/// This Dart module just:
/// 1. Calls `rac_backend_onnx_register()` to register the backend
/// 2. The core SDK handles all operations via component APIs
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere_onnx/runanywhere_onnx.dart';
///
/// // Register the module (matches Swift: ONNX.register())
/// await Onnx.register();
///
/// // Add STT model
/// Onnx.addModel(
///   name: 'Sherpa Whisper Tiny',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
/// );
/// ```
library runanywhere_onnx;

import 'dart:async';

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/runanywhere.dart' show RunAnywhere;
import 'package:runanywhere_onnx/native/onnx_bindings.dart';

// Re-export for backward compatibility
export 'onnx_download_strategy.dart';

/// ONNX Runtime module for STT, TTS, and VAD services.
///
/// Provides speech-to-text, text-to-speech, and voice activity detection
/// capabilities using ONNX Runtime with models like Whisper, Piper, and Silero.
///
/// Matches Swift `ONNX` enum from ONNXRuntime/ONNX.swift.
class Onnx implements RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches Swift enum pattern)
  // ============================================================================

  static final Onnx _instance = Onnx._internal();
  static Onnx get module => _instance;
  Onnx._internal();

  // ============================================================================
  // Module Info (matches Swift exactly)
  // ============================================================================

  /// Current version of the ONNX Runtime module
  static const String version = '2.0.0';

  /// ONNX Runtime library version (underlying C library)
  static const String onnxRuntimeVersion = '1.23.2';

  // ============================================================================
  // RunAnywhereModule Conformance (matches Swift exactly)
  // ============================================================================

  @override
  String get moduleId => 'onnx';

  @override
  String get moduleName => 'ONNX Runtime';

  @override
  Set<SDKComponent> get capabilities => {
        SDKComponent.stt,
        SDKComponent.tts,
        SDKComponent.vad,
      };

  @override
  int get defaultPriority => 100;

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.onnx;

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static OnnxBindings? _bindings;
  static final _logger = SDKLogger('Onnx');

  /// Internal model registry for models added via addModel
  static final List<ModelInfo> _registeredModels = [];

  // ============================================================================
  // Registration (matches Swift ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX backend with the C++ service registry.
  ///
  /// This calls `rac_backend_onnx_register()` to register all ONNX
  /// service providers (STT, TTS, VAD) with the C++ commons layer.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  static Future<void> register({int priority = 100}) async {
    if (_isRegistered) {
      _logger.debug('ONNX already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('ONNX native library not available');
      return;
    }

    _logger.info('Registering ONNX backend with C++ registry...');

    try {
      _bindings = OnnxBindings();
      final result = _bindings!.register();

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.warning('C++ backend registration returned: $result');
        return;
      }

      _isRegistered = true;
      _logger.info('ONNX backend registered successfully (STT + TTS + VAD)');
    } catch (e) {
      _logger.error('OnnxBindings not available: $e');
    }
  }

  /// Unregister the ONNX backend from C++ registry.
  static void unregister() {
    if (!_isRegistered) return;

    _bindings?.unregister();
    _isRegistered = false;
    _logger.info('ONNX backend unregistered');
  }

  // ============================================================================
  // Model Handling (matches Swift exactly)
  // ============================================================================

  /// Check if the native backend is available on this platform.
  ///
  /// On iOS: Checks DynamicLibrary.process() for statically linked symbols
  /// On Android: Checks if librac_backend_onnx_jni.so can be loaded
  static bool get isAvailable => OnnxBindings.checkAvailability();

  /// Check if ONNX can handle a given model for STT.
  static bool canHandleSTT(String? modelId) {
    if (modelId == null) return false;
    final lowercased = modelId.toLowerCase();
    return lowercased.contains('whisper') ||
        lowercased.contains('zipformer') ||
        lowercased.contains('paraformer');
  }

  /// Check if ONNX can handle a given model for TTS.
  static bool canHandleTTS(String? modelId) {
    if (modelId == null) return false;
    final lowercased = modelId.toLowerCase();
    return lowercased.contains('piper') || lowercased.contains('vits');
  }

  /// Check if ONNX can handle VAD (always true for Silero VAD).
  static bool canHandleVAD(String? modelId) {
    return true; // ONNX Silero VAD is the default
  }

  // ============================================================================
  // Model Registration (convenience API)
  // ============================================================================

  /// Add an ONNX model to the registry.
  ///
  /// This is a convenience method that registers a model with the SDK.
  /// The model will be associated with the ONNX backend.
  ///
  /// Matches Swift pattern - models are registered globally via RunAnywhere.
  static void addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory modality = ModelCategory.language,
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
      framework: InferenceFramework.onnx,
      modality: modality,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    // Keep local reference for convenience
    _registeredModels.add(model);
    _logger.info('Added ONNX model: $name ($modelId) [$modality]');
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
    _logger.info('ONNX disposed');
  }

  // ============================================================================
  // Auto-Registration (matches Swift exactly)
  // ============================================================================

  /// Enable auto-registration for this module.
  /// Call this function to trigger C++ backend registration.
  static void autoRegister() {
    unawaited(register());
  }
}
