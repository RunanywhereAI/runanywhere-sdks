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

  // Symbol lookup scope for Sherpa + plugin-registry symbols. On Android these
  // live in sibling .so files (librac_backend_sherpa.so, librac_commons.so)
  // that OnnxPlugin.kt + RunAnywhereBridge.kt preload, so we resolve them via
  // RTLD_DEFAULT (`DynamicLibrary.process()`) rather than searching `_lib`
  // (which is just librac_backend_onnx.so on Android). On iOS/macOS the
  // statically linked XCFramework already exposes every symbol through
  // `DynamicLibrary.process()`, so this collapses to the same lookup we use
  // for the ONNX backend.
  final DynamicLibrary _pluginRegistryLib;

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
  OnnxBindings()
      : _lib = _loadLibrary(),
        _pluginRegistryLib = _loadPluginRegistryLibrary() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  OnnxBindings.withLibrary(this._lib)
      : _pluginRegistryLib = _loadPluginRegistryLibrary() {
    _bindFunctions();
  }

  /// Load the correct library for the current platform.
  static DynamicLibrary _loadLibrary() {
    return loadBackendLibrary();
  }

  /// Load the symbol scope used for Sherpa + unified plugin-registry lookups.
  ///
  /// On Android, the Sherpa register entry point lives in
  /// `librac_backend_sherpa.so` and the plugin-registry symbols
  /// (`rac_plugin_register` / `rac_plugin_unregister`) live in
  /// `librac_commons.so`. `OnnxPlugin.kt` already calls
  /// `System.loadLibrary("rac_backend_sherpa")` from its static initializer
  /// and `RunAnywhereBridge.kt` pulls in `librac_commons.so` transitively via
  /// `librunanywhere_jni.so`, but in practice Dart FFI can race the plugin
  /// static initializers (the Onnx Dart module is exposed before the Flutter
  /// embedder finishes class loading the plugin) — and even when the JVM has
  /// loaded the .so, `dlsym(RTLD_DEFAULT, ...)` (`DynamicLibrary.process()`)
  /// does not see those symbols on every Android device. We therefore open
  /// `librac_backend_sherpa.so` directly from Dart so the returned handle has
  /// the Sherpa entry symbols and (via the NEEDED dependency) the
  /// commons-side plugin registry symbols. This is the same workaround the
  /// React-Native ONNX hybrid uses (it calls the C entry points directly
  /// from native C++, never through `RTLD_DEFAULT`).
  ///
  /// On iOS/macOS everything is statically linked into the host binary, so
  /// `DynamicLibrary.process()` finds every exported symbol — the same lookup
  /// path that `PlatformLoader.loadCommons()` returns.
  static DynamicLibrary _loadPluginRegistryLibrary() {
    if (Platform.isAndroid) {
      // On Android open the Sherpa backend explicitly. This guarantees the
      // Sherpa entry symbols are visible to FFI lookups even if OnnxPlugin's
      // static initializer has not yet run (or ran on a different namespace).
      // The .so's NEEDED dependency on librac_commons.so means the dynamic
      // linker also resolves rac_plugin_register / rac_plugin_unregister so
      // the same handle can be used for both Sherpa and unified plugin
      // registry lookups.
      try {
        return DynamicLibrary.open('librac_backend_sherpa.so');
      } catch (_) {
        // Library may not be bundled in stripped-down builds. Fall through
        // to RTLD_DEFAULT below — if the symbols are nowhere to be found,
        // `registerSherpa()` returns RAC_ERROR_NOT_SUPPORTED instead of
        // crashing.
      }
    }
    try {
      return DynamicLibrary.process();
    } catch (_) {
      // `DynamicLibrary.process()` should not fail on supported platforms,
      // but if it does, fall through to the ONNX backend library — Sherpa
      // bindings will end up null and `registerSherpa()` will return
      // RAC_ERROR_NOT_SUPPORTED instead of crashing.
      return loadBackendLibrary();
    }
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
    // dart:ffi requires concrete native function types at lookupFunction call
    // sites - we cannot route through a generic helper. Each binding is
    // wrapped in its own try/catch so a missing symbol on one platform
    // (e.g. Sherpa wrapper on iOS static) does not crash the others.
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

    // Sherpa lifecycle. Prefer the explicit wrapper (Android dynamic linkage);
    // if absent (iOS XCFramework drops the wrapper), bind the plugin-entry
    // pair so we can register Sherpa through the unified plugin registry.
    //
    // Resolve these via `_pluginRegistryLib`
    // (`DynamicLibrary.process()` on Android, statically linked binary on
    // iOS/macOS) instead of `_lib`. `_lib` is just `librac_backend_onnx.so` on
    // Android — it does NOT export `rac_backend_sherpa_register`,
    // `rac_plugin_entry_sherpa`, `rac_plugin_register`, or
    // `rac_plugin_unregister`. Those live in `librac_backend_sherpa.so` and
    // `librac_commons.so` respectively. OnnxPlugin.kt + RunAnywhereBridge.kt
    // preload both, so RTLD_DEFAULT resolves them at FFI lookup time.
    try {
      _sherpaRegister = _pluginRegistryLib.lookupFunction<
          RacBackendSherpaRegisterNative,
          RacBackendSherpaRegisterDart>('rac_backend_sherpa_register');
    } catch (_) {
      _sherpaRegister = null;
    }
    try {
      _sherpaUnregister = _pluginRegistryLib.lookupFunction<
          RacBackendSherpaUnregisterNative,
          RacBackendSherpaUnregisterDart>('rac_backend_sherpa_unregister');
    } catch (_) {
      _sherpaUnregister = null;
    }
    try {
      _sherpaPluginEntry = _pluginRegistryLib.lookupFunction<
          RacPluginEntrySherpaNative,
          RacPluginEntrySherpaDart>('rac_plugin_entry_sherpa');
    } catch (_) {
      _sherpaPluginEntry = null;
    }
    try {
      _pluginRegister = _pluginRegistryLib
          .lookupFunction<RacPluginRegisterNative, RacPluginRegisterDart>(
              'rac_plugin_register');
    } catch (_) {
      _pluginRegister = null;
    }
    try {
      _pluginUnregister = _pluginRegistryLib
          .lookupFunction<RacPluginUnregisterNative, RacPluginUnregisterDart>(
              'rac_plugin_unregister');
    } catch (_) {
      _pluginUnregister = null;
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
