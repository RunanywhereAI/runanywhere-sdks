import 'dart:ffi';
import 'dart:io';

import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Minimal LlamaCPP backend FFI bindings.
///
/// This is a **thin wrapper** that only provides:
/// - `register()` - calls `rac_backend_llamacpp_register()`
/// - `unregister()` - calls `rac_backend_llamacpp_unregister()`
///
/// All other LLM operations (create, load, generate, etc.) are handled by
/// the core SDK via `rac_llm_component_*` functions in RACommons.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendLlamaCPP) handles all business logic:
/// - Service provider registration with the C++ service registry
/// - Model loading and inference
/// - Streaming generation
///
/// This Dart code just:
/// 1. Calls `rac_backend_llamacpp_register()` to register the backend
/// 2. The core SDK's `NativeBackend` handles all LLM operations via `rac_llm_component_*`
class LlamaCppBindings {
  final DynamicLibrary _lib;

  // Function pointers - only registration functions
  late final RacBackendLlamacppRegisterDart? _register;
  late final RacBackendLlamacppUnregisterDart? _unregister;

  /// Create bindings using the appropriate library for each platform.
  ///
  /// - iOS: Uses DynamicLibrary.process() for statically linked XCFramework
  /// - Android: Loads librac_backend_llamacpp_jni.so separately
  LlamaCppBindings() : _lib = _loadLibrary() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  LlamaCppBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  /// Load the correct library for the current platform.
  static DynamicLibrary _loadLibrary() {
    return loadBackendLibrary();
  }

  /// Load the LlamaCpp backend library.
  ///
  /// On iOS/macOS: Uses DynamicLibrary.process() for statically linked XCFramework
  /// On Android: Loads librac_backend_llamacpp_jni.so or librunanywhere_llamacpp.so
  ///
  /// This is exposed as a static method so it can be used by [LlamaCpp.isAvailable].
  static DynamicLibrary loadBackendLibrary() {
    if (Platform.isAndroid) {
      // On Android, the LlamaCpp backend is in a separate .so file.
      // We need to ensure librac_commons.so is loaded first (dependency).
      try {
        PlatformLoader.loadCommons();
      } catch (_) {
        // Ignore - continue trying to load backend
      }

      // Try different naming conventions for the backend library
      final libraryNames = [
        'librac_backend_llamacpp_jni.so',
        'librunanywhere_llamacpp.so',
      ];

      for (final name in libraryNames) {
        try {
          return DynamicLibrary.open(name);
        } catch (_) {
          // Try next name
        }
      }

      // If backend library not found, throw an error
      throw ArgumentError(
        'Could not load LlamaCpp backend library on Android. '
        'Tried: ${libraryNames.join(", ")}',
      );
    }

    // On iOS/macOS, everything is statically linked
    return PlatformLoader.loadCommons();
  }

  /// Check if the LlamaCpp backend library can be loaded on this platform.
  static bool checkAvailability() {
    try {
      final lib = loadBackendLibrary();
      lib.lookup<NativeFunction<Int32 Function()>>(
          'rac_backend_llamacpp_register');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    // Backend registration - from RABackendLlamaCPP
    try {
      _register = _lib.lookupFunction<RacBackendLlamacppRegisterNative,
          RacBackendLlamacppRegisterDart>('rac_backend_llamacpp_register');
    } catch (_) {
      _register = null;
    }

    try {
      _unregister = _lib.lookupFunction<RacBackendLlamacppUnregisterNative,
          RacBackendLlamacppUnregisterDart>('rac_backend_llamacpp_unregister');
    } catch (_) {
      _unregister = null;
    }
  }

  /// Check if bindings are available.
  bool get isAvailable => _register != null;

  /// Register the LlamaCPP backend with the C++ service registry.
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

  /// Unregister the LlamaCPP backend from C++ registry.
  int unregister() {
    if (_unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unregister!();
  }
}
