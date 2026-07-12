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
/// // Register models through RunAnywhere.models.
/// // The commons registry/router owns framework selection and routing.
/// ```
library;

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_onnx/native/onnx_bindings.dart';

/// ONNX Runtime module for STT, TTS, and VAD services.
///
/// Provides speech-to-text, text-to-speech, and voice activity detection
/// capabilities using ONNX Runtime with models like Whisper, Piper, and Silero.
///
/// Matches Swift `ONNX` enum from ONNXRuntime/ONNX.swift.
class Onnx {
  Onnx._();

  // ============================================================================
  // Module Info (matches Swift exactly)
  // ============================================================================

  /// Current version of the ONNX Runtime module
  static const String version = '2.0.0';

  /// ONNX Runtime library version (underlying C library)
  static const String onnxRuntimeVersion = '1.24.3';

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static bool _isSherpaRegistered = false;
  static OnnxBindings? _bindings;
  static final _logger = SDKLogger('Onnx');

  // ============================================================================
  // Registration (matches Swift ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX backend with the C++ service registry.
  ///
  /// This calls `rac_backend_onnx_register()` to register the generic ONNX
  /// backend (embeddings + Silero VAD) and then registers the Sherpa-ONNX
  /// engine plugin so STT (Whisper/Zipformer/Paraformer), TTS (Piper/VITS),
  /// and Sherpa-backed VAD models with `framework == .sherpa` can resolve
  /// through the unified plugin router. The two plugins are peers: "onnx"
  /// owns embeddings, "sherpa" owns speech primitives. Mirrors Swift
  /// `ONNX.register()` (ONNXRuntime/ONNX.swift).
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
      _logger.info('ONNX backend registered successfully (embeddings + plugin)');

      _registerSherpa();
    } catch (e) {
      _logger.error('OnnxBindings not available: $e');
    }
  }

  /// Register the Sherpa-ONNX engine plugin so the commons plugin router can
  /// resolve `framework == .sherpa` models. Mirrors Swift
  /// `ONNX.registerSherpaPlugin()`.
  static void _registerSherpa() {
    if (_isSherpaRegistered) return;
    final bindings = _bindings;
    if (bindings == null) return;

    final result = bindings.registerSherpa();
    if (result == RacResultCode.success ||
        result == RacResultCode.errorModuleAlreadyRegistered) {
      _isSherpaRegistered = true;
      _logger.info(
        'Sherpa engine plugin registered (STT + TTS + VAD via Sherpa-ONNX)',
      );
    } else if (result == RacResultCode.errorNotSupported) {
      _logger.warning(
        'Sherpa engine plugin entry not exported by this build '
        '— Sherpa STT/TTS/VAD will not route',
      );
    } else {
      _logger.error('Sherpa plugin registration failed: $result');
    }
  }

  /// Unregister the ONNX backend from C++ registry.
  static void unregister() {
    if (_isSherpaRegistered) {
      _bindings?.unregisterSherpa();
      _isSherpaRegistered = false;
      _logger.info('Sherpa engine plugin unregistered');
    }

    if (!_isRegistered) return;

    _bindings?.unregister();
    _isRegistered = false;
    _logger.info('ONNX backend unregistered');
  }

  /// Check if the native backend is available on this platform.
  ///
  /// On iOS: Checks DynamicLibrary.process() for statically linked symbols
  /// On Android: Checks if librac_backend_onnx_jni.so can be loaded
  static bool get isAvailable => OnnxBindings.checkAvailability();

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources
  static void dispose() {
    _bindings = null;
    _isRegistered = false;
    _isSherpaRegistered = false;
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
