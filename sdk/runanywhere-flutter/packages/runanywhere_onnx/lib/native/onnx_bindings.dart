import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

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

  // Sherpa registration. On Android the librac_backend_sherpa.so is preloaded
  // by OnnxPlugin.kt; on iOS the symbol comes from the statically linked
  // XCFramework. We bind the explicit register entry point if exported and
  // fall back to the plugin-entry + plugin-register pair (Swift parity)
  // when the wrapper symbol is unavailable.
  late final RacBackendSherpaRegisterDart? _sherpaRegister;
  late final RacBackendSherpaUnregisterDart? _sherpaUnregister;
  late final RacPluginEntrySherpaDart? _sherpaPluginEntry;
  late final RacPluginRegisterDart? _pluginRegister;
  late final RacPluginUnregisterDart? _pluginUnregister;

  /// Create bindings using the appropriate library for each platform.
  ///
  /// - iOS: Uses DynamicLibrary.process() for statically linked XCFramework
  /// - Android: Loads librac_backend_onnx_jni.so separately
  OnnxBindings() : _lib = _loadLibrary() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  OnnxBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  /// Load the correct library for the current platform.
  static DynamicLibrary _loadLibrary() {
    return loadBackendLibrary();
  }

  /// Load the ONNX backend library.
  ///
  /// On iOS/macOS: Uses DynamicLibrary.process() for statically linked XCFramework
  /// On Android: Loads librac_backend_onnx_jni.so or librunanywhere_onnx.so
  ///
  /// This is exposed as a static method so it can be used by [Onnx.isAvailable].
  static DynamicLibrary loadBackendLibrary() {
    if (Platform.isAndroid) {
      // On Android, the ONNX backend is in a separate .so file.
      // We need to ensure librac_commons.so is loaded first (dependency).
      try {
        PlatformLoader.loadCommons();
      } catch (_) {
        // Ignore - continue trying to load backend
      }

      // Try different naming conventions for the backend library
      final libraryNames = [
        'librac_backend_onnx.so',
        'librac_backend_onnx_jni.so',
        'librunanywhere_onnx.so',
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
        'Could not load ONNX backend library on Android. '
        'Tried: ${libraryNames.join(", ")}',
      );
    }

    // On iOS/macOS, everything is statically linked
    return PlatformLoader.loadCommons();
  }

  /// Check if the ONNX backend library can be loaded on this platform.
  static bool checkAvailability() {
    try {
      final lib = loadBackendLibrary();
      lib.lookup<NativeFunction<Int32 Function()>>('rac_backend_onnx_register');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    _register = _lookup<RacBackendOnnxRegisterNative,
        RacBackendOnnxRegisterDart>('rac_backend_onnx_register');
    _unregister = _lookup<RacBackendOnnxUnregisterNative,
        RacBackendOnnxUnregisterDart>('rac_backend_onnx_unregister');

    // Sherpa lifecycle. Prefer the explicit wrapper (Android dynamic linkage);
    // if absent (iOS XCFramework drops the wrapper), bind the plugin-entry
    // pair so we can register Sherpa through the unified plugin registry.
    _sherpaRegister = _lookup<RacBackendSherpaRegisterNative,
        RacBackendSherpaRegisterDart>('rac_backend_sherpa_register');
    _sherpaUnregister = _lookup<RacBackendSherpaUnregisterNative,
        RacBackendSherpaUnregisterDart>('rac_backend_sherpa_unregister');
    _sherpaPluginEntry = _lookup<RacPluginEntrySherpaNative,
        RacPluginEntrySherpaDart>('rac_plugin_entry_sherpa');
    _pluginRegister =
        _lookup<RacPluginRegisterNative, RacPluginRegisterDart>(
            'rac_plugin_register');
    _pluginUnregister =
        _lookup<RacPluginUnregisterNative, RacPluginUnregisterDart>(
            'rac_plugin_unregister');
  }

  T? _lookup<NF extends Function, T extends Function>(String symbol) {
    try {
      return _lib.lookupFunction<NF, T>(symbol);
    } catch (_) {
      return null;
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
    return _register();
  }

  /// Unregister the ONNX backend from C++ registry.
  int unregister() {
    if (_unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unregister();
  }

  /// Register the Sherpa engine plugin with the unified plugin registry.
  ///
  /// Mirrors Swift `ONNX.registerSherpaPlugin()`: on Android we call the
  /// explicit `rac_backend_sherpa_register()` wrapper exported by
  /// librac_backend_sherpa.so; on iOS/static hosts the wrapper is not
  /// exported, so we fall back to `rac_plugin_register(rac_plugin_entry_sherpa())`.
  ///
  /// Returns RAC_SUCCESS / RAC_ERROR_MODULE_ALREADY_REGISTERED on success.
  int registerSherpa() {
    if (_sherpaRegister != null) {
      return _sherpaRegister();
    }
    final entry = _sherpaPluginEntry;
    final register = _pluginRegister;
    if (entry == null || register == null) {
      return RacResultCode.errorNotSupported;
    }
    final vtable = entry();
    if (vtable == nullptr) {
      return RacResultCode.errorNotSupported;
    }
    return register(vtable);
  }

  /// Unregister the Sherpa engine plugin.
  int unregisterSherpa() {
    if (_sherpaUnregister != null) {
      return _sherpaUnregister();
    }
    final unregister = _pluginUnregister;
    if (unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    final name = 'sherpa'.toNativeUtf8();
    try {
      return unregister(name.cast<Char>());
    } finally {
      malloc.free(name);
    }
  }
}

// FFI type definitions for ONNX backend registration
typedef RacBackendOnnxRegisterNative = Int32 Function();
typedef RacBackendOnnxRegisterDart = int Function();
typedef RacBackendOnnxUnregisterNative = Int32 Function();
typedef RacBackendOnnxUnregisterDart = int Function();

// FFI type definitions for Sherpa backend registration
typedef RacBackendSherpaRegisterNative = Int32 Function();
typedef RacBackendSherpaRegisterDart = int Function();
typedef RacBackendSherpaUnregisterNative = Int32 Function();
typedef RacBackendSherpaUnregisterDart = int Function();

// FFI type definitions for the unified plugin registry. The vtable is an
// opaque pointer here - we do not dereference it from Dart, the C registry
// validates and stores it internally.
typedef RacPluginEntrySherpaNative = Pointer<Void> Function();
typedef RacPluginEntrySherpaDart = Pointer<Void> Function();
typedef RacPluginRegisterNative = Int32 Function(Pointer<Void>);
typedef RacPluginRegisterDart = int Function(Pointer<Void>);
typedef RacPluginUnregisterNative = Int32 Function(Pointer<Char>);
typedef RacPluginUnregisterDart = int Function(Pointer<Char>);
