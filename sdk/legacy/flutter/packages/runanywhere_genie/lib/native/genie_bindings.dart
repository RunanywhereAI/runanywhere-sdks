import 'dart:ffi';
import 'dart:io';

import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Minimal Genie NPU backend FFI bindings.
///
/// This is a **thin wrapper** that only provides:
/// - `register()` - calls `rac_backend_genie_register()`
/// - `unregister()` - calls `rac_backend_genie_unregister()`
///
/// All other LLM operations (create, load, generate, etc.) are handled by
/// the core SDK via `rac_llm_component_*` functions in RACommons.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendGenie) handles all business logic:
/// - Service provider registration with the C++ service registry
/// - Model loading and inference on Snapdragon NPU
/// - Streaming generation
///
/// This Dart code just:
/// 1. Calls `rac_backend_genie_register()` to register the backend
/// 2. The core SDK's `NativeBackend` handles all LLM operations via `rac_llm_component_*`
///
/// ## Platform Support
///
/// Genie is Android/Snapdragon only. On iOS and other platforms,
/// `checkAvailability()` always returns false.
class GenieBindings {
  final DynamicLibrary _lib;

  // Function pointers - only registration functions
  late final RacBackendGenieRegisterDart? _register;
  late final RacBackendGenieUnregisterDart? _unregister;

  /// Create bindings using the appropriate library for each platform.
  ///
  /// - Android: Loads librac_backend_genie_jni.so separately
  /// - iOS/other: Returns DynamicLibrary.executable() but symbols won't be found
  GenieBindings() : _lib = _loadLibrary() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  GenieBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  /// Load the correct library for the current platform.
  static DynamicLibrary _loadLibrary() {
    return loadBackendLibrary();
  }

  /// Load the Genie backend library.
  ///
  /// On Android: Loads librac_backend_genie_jni.so or librunanywhere_genie.so
  /// On iOS/other: Returns DynamicLibrary.executable() (symbols won't be available)
  ///
  /// This is exposed as a static method so it can be used by [Genie.isAvailable].
  static DynamicLibrary loadBackendLibrary() {
    if (Platform.isAndroid) {
      // On Android, the Genie backend is in a separate .so file.
      // We need to ensure librac_commons.so is loaded first (dependency).
      try {
        PlatformLoader.loadCommons();
      } catch (_) {
        // Ignore - continue trying to load backend
      }

      // Try different naming conventions for the backend library
      final libraryNames = [
        'librac_backend_genie_jni.so',
        'librunanywhere_genie.so',
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
        'Could not load Genie backend library on Android. '
        'Tried: ${libraryNames.join(", ")}',
      );
    }

    // On iOS/macOS, Genie is not supported but we return executable
    // for Flutter plugin system compatibility
    return PlatformLoader.loadCommons();
  }

  /// Check if the Genie backend library can be loaded on this platform.
  ///
  /// Always returns false on non-Android platforms since Genie
  /// is a Snapdragon NPU-only backend.
  static bool checkAvailability() {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final lib = loadBackendLibrary();
      lib.lookup<NativeFunction<Int32 Function()>>(
          'rac_backend_genie_register');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    // Backend registration - from RABackendGenie
    try {
      _register = _lib.lookupFunction<RacBackendGenieRegisterNative,
          RacBackendGenieRegisterDart>('rac_backend_genie_register');
    } catch (_) {
      _register = null;
    }

    try {
      _unregister = _lib.lookupFunction<RacBackendGenieUnregisterNative,
          RacBackendGenieUnregisterDart>('rac_backend_genie_unregister');
    } catch (_) {
      _unregister = null;
    }
  }

  /// Check if bindings are available.
  bool get isAvailable => _register != null;

  /// Register the Genie backend with the C++ service registry.
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

  /// Unregister the Genie backend from C++ registry.
  int unregister() {
    if (_unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unregister!();
  }
}

// =============================================================================
// FFI Type Definitions for Genie Backend
// =============================================================================

/// rac_result_t rac_backend_genie_register(void)
typedef RacBackendGenieRegisterNative = Int32 Function();
typedef RacBackendGenieRegisterDart = int Function();

/// rac_result_t rac_backend_genie_unregister(void)
typedef RacBackendGenieUnregisterNative = Int32 Function();
typedef RacBackendGenieUnregisterDart = int Function();
