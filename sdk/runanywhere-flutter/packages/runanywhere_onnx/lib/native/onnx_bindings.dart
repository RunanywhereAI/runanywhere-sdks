import 'dart:ffi';

import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Minimal ONNX backend FFI bindings.
///
/// This is a **thin wrapper** that only provides:
/// - `register()` - calls `rac_backend_onnx_register()`
/// - `unregister()` - calls `rac_backend_onnx_unregister()`
///
/// All other STT/TTS/VAD operations are handled by the core SDK via
/// `rac_stt_component_*`, `rac_tts_component_*`, `rac_vad_component_*` functions.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendONNX) handles all business logic:
/// - Service provider registration with the C++ service registry
/// - Model loading and inference for STT/TTS/VAD
/// - Streaming transcription
///
/// This Dart code just:
/// 1. Calls `rac_backend_onnx_register()` to register the backend
/// 2. The core SDK handles all operations via component APIs
class OnnxBindings {
  final DynamicLibrary _lib;

  // Function pointers - only registration functions
  late final RacBackendOnnxRegisterDart? _register;
  late final RacBackendOnnxUnregisterDart? _unregister;

  /// Create bindings using DynamicLibrary.process() for iOS (statically linked)
  /// or the appropriate loader for other platforms.
  OnnxBindings() : _lib = PlatformLoader.loadCommons() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  OnnxBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  void _bindFunctions() {
    // Backend registration - from RABackendONNX
    try {
      _register = _lib.lookupFunction<RacBackendOnnxRegisterNative,
          RacBackendOnnxRegisterDart>('rac_backend_onnx_register');
    } catch (_) {
      _register = null;
    }

    try {
      _unregister = _lib.lookupFunction<RacBackendOnnxUnregisterNative,
          RacBackendOnnxUnregisterDart>('rac_backend_onnx_unregister');
    } catch (_) {
      _unregister = null;
    }
  }

  /// Check if bindings are available.
  bool get isAvailable => _register != null;

  /// Register the ONNX backend with the C++ service registry.
  ///
  /// Returns RAC_SUCCESS (0) on success, or an error code.
  /// Safe to call multiple times - returns RAC_ERROR_MODULE_ALREADY_REGISTERED
  /// if already registered.
  int register() {
    if (_register == null) {
      return RacResultCode.errorNotSupported;
    }
    return _register!();
  }

  /// Unregister the ONNX backend from C++ registry.
  int unregister() {
    if (_unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unregister!();
  }
}

// FFI type definitions for ONNX backend registration
typedef RacBackendOnnxRegisterNative = Int32 Function();
typedef RacBackendOnnxRegisterDart = int Function();
typedef RacBackendOnnxUnregisterNative = Int32 Function();
typedef RacBackendOnnxUnregisterDart = int Function();
