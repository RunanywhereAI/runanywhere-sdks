import 'dart:ffi';
import 'dart:io';

/// Platform-specific library loader for RunAnywhere native libraries.
///
/// The new architecture uses separate libraries:
/// - RACommons: Core functionality (logging, module registry, platform adapter)
/// - RABackendLlamaCPP: LLM text generation with llama.cpp
/// - RABackendONNX: STT/TTS/VAD with ONNX Runtime
///
/// ## iOS
/// XCFrameworks are statically linked into the app binary via CocoaPods.
/// All symbols are available via `DynamicLibrary.executable()`.
///
/// ## Android
/// .so files are loaded from jniLibs via `DynamicLibrary.open()`.
/// The Gradle build system handles downloading and placing the .so files.
class PlatformLoader {
  // Cached library instances
  static DynamicLibrary? _commonsLibrary;
  static DynamicLibrary? _llamacppLibrary;
  static DynamicLibrary? _onnxLibrary;
  static String? _loadError;

  // Library names (without platform-specific prefix/suffix)
  // On Android: librac_commons.so, librunanywhere_llamacpp.so, librunanywhere_onnx.so
  // On iOS/macOS: RACommons.xcframework, RABackendLlamaCPP.xcframework, RABackendONNX.xcframework
  static const String _commonsLibraryName = 'rac_commons';
  static const String _llamacppLibraryName = 'runanywhere_llamacpp';
  static const String _onnxLibraryName = 'runanywhere_onnx';

  // =============================================================================
  // Main Loaders
  // =============================================================================

  /// Load the RACommons native library.
  ///
  /// This is the core library that provides:
  /// - Module registry
  /// - Service provider registry
  /// - Platform adapter interface
  /// - Logging and error handling
  static DynamicLibrary loadCommons() {
    if (_commonsLibrary != null) {
      return _commonsLibrary!;
    }

    try {
      _commonsLibrary = _loadLibrary(_commonsLibraryName);
      _loadError = null;
      return _commonsLibrary!;
    } catch (e) {
      _loadError = e.toString();
      rethrow;
    }
  }

  /// Load the RABackendLlamaCPP native library.
  ///
  /// This library provides:
  /// - LLM text generation
  /// - Streaming generation
  /// - Model loading/unloading
  static DynamicLibrary loadLlamaCpp() {
    if (_llamacppLibrary != null) {
      return _llamacppLibrary!;
    }

    try {
      _llamacppLibrary = _loadLibrary(_llamacppLibraryName);
      return _llamacppLibrary!;
    } catch (e) {
      _loadError = e.toString();
      rethrow;
    }
  }

  /// Load the RABackendONNX native library.
  ///
  /// This library provides:
  /// - STT (Speech-to-Text) with Sherpa-ONNX
  /// - TTS (Text-to-Speech) with VITS models
  /// - VAD (Voice Activity Detection)
  static DynamicLibrary loadOnnx() {
    if (_onnxLibrary != null) {
      return _onnxLibrary!;
    }

    try {
      _onnxLibrary = _loadLibrary(_onnxLibraryName);
      return _onnxLibrary!;
    } catch (e) {
      _loadError = e.toString();
      rethrow;
    }
  }

  /// Legacy method for backward compatibility.
  /// Loads the commons library by default.
  static DynamicLibrary load() => loadCommons();

  /// Try to load the commons library, returning null if it fails.
  static DynamicLibrary? tryLoad() {
    try {
      return loadCommons();
    } catch (_) {
      return null;
    }
  }

  // =============================================================================
  // Platform-Specific Loading
  // =============================================================================

  static DynamicLibrary _loadLibrary(String libraryName) {
    if (Platform.isAndroid) {
      return _loadAndroid(libraryName);
    } else if (Platform.isIOS) {
      return _loadIOS(libraryName);
    } else if (Platform.isMacOS) {
      return _loadMacOS(libraryName);
    } else if (Platform.isLinux) {
      return _loadLinux(libraryName);
    } else if (Platform.isWindows) {
      return _loadWindows(libraryName);
    }

    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} is not supported. '
      'Supported platforms: Android, iOS, macOS, Linux, Windows.',
    );
  }

  /// Load on Android from jniLibs.
  ///
  /// Android libraries are placed in jniLibs by the Gradle build:
  /// - src/main/jniLibs/arm64-v8a/lib*.so
  /// - src/main/jniLibs/armeabi-v7a/lib*.so
  /// - src/main/jniLibs/x86_64/lib*.so
  static DynamicLibrary _loadAndroid(String libraryName) {
    // On Android, the system loader handles dependencies automatically
    // when libraries are in jniLibs. Just open the requested library.
    //
    // Library naming conventions:
    // - RACommons -> libracommons.so
    // - RABackendLlamaCPP -> librabackendllamacpp.so
    // - RABackendONNX -> librabackendonnx.so
    final soName = 'lib$libraryName.so';

    try {
      return DynamicLibrary.open(soName);
    } catch (e) {
      // Try alternate naming conventions
      final alternateName = 'lib${_androidLibraryName(libraryName)}.so';
      if (alternateName != soName) {
        try {
          return DynamicLibrary.open(alternateName);
        } catch (_) {
          // Fall through to throw original error
        }
      }
      throw ArgumentError(
        'Could not load $soName on Android: $e. '
        'Ensure the native library is built and placed in jniLibs.',
      );
    }
  }

  /// Map library name to alternate Android convention (for fallback)
  static String _androidLibraryName(String name) {
    switch (name) {
      case 'rac_commons':
        return 'runanywhere_jni'; // JNI wrapper for commons
      case 'runanywhere_llamacpp':
        return 'rac_backend_llamacpp_jni'; // JNI wrapper for llamacpp
      case 'runanywhere_onnx':
        return 'rac_backend_onnx_jni'; // JNI wrapper for onnx
      default:
        return name;
    }
  }

  /// Load on iOS using executable() for statically linked XCFramework.
  ///
  /// iOS uses static linking via XCFramework in podspec.
  /// All symbols from RACommons, RABackendLlamaCPP, and RABackendONNX
  /// are linked into the main executable.
  static DynamicLibrary _loadIOS(String libraryName) {
    // On iOS, XCFrameworks are statically linked into the app binary
    // via CocoaPods. All symbols are available in the main executable.
    //
    // The podspec files configure:
    // - runanywhere.podspec -> links RACommons.xcframework
    // - runanywhere_llamacpp.podspec -> links RABackendLlamaCPP.xcframework
    // - runanywhere_onnx.podspec -> links RABackendONNX.xcframework
    return DynamicLibrary.executable();
  }

  /// Load on macOS for development/testing.
  ///
  /// macOS supports both:
  /// 1. Static linking via XCFramework (release builds)
  /// 2. Dynamic loading of .dylib (development builds)
  static DynamicLibrary _loadMacOS(String libraryName) {
    // First try executable() for statically linked builds (like iOS)
    try {
      final lib = DynamicLibrary.executable();
      // Verify we can find a symbol from the requested library
      if (_verifyMacOSLibrary(lib, libraryName)) {
        return lib;
      }
    } catch (_) {
      // Fall through to dynamic loading
    }

    // Try process() for dynamically linked builds
    try {
      final lib = DynamicLibrary.process();
      if (_verifyMacOSLibrary(lib, libraryName)) {
        return lib;
      }
    } catch (_) {
      // Fall through to explicit path loading
    }

    // Try explicit dylib paths for development
    final dylibName = 'lib$libraryName.dylib';
    final searchPaths = _getMacOSSearchPaths(dylibName);

    for (final path in searchPaths) {
      if (File(path).existsSync()) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          // Try next path
        }
      }
    }

    // Last resort: let the system find it
    try {
      return DynamicLibrary.open(dylibName);
    } catch (e) {
      throw ArgumentError(
        'Could not load $dylibName on macOS. '
        'Tried: ${searchPaths.join(", ")}. Error: $e',
      );
    }
  }

  /// Verify macOS library has expected symbols
  static bool _verifyMacOSLibrary(DynamicLibrary lib, String libraryName) {
    try {
      // Check for a known symbol from each library
      switch (libraryName) {
        case 'racommons':
          lib.lookup('rac_init');
          return true;
        case 'rabackendllamacpp':
          lib.lookup('rac_backend_llamacpp_register');
          return true;
        case 'rabackendonnx':
          lib.lookup('rac_stt_onnx_create');
          return true;
        default:
          return true;
      }
    } catch (_) {
      return false;
    }
  }

  /// Get macOS search paths for dylib
  static List<String> _getMacOSSearchPaths(String dylibName) {
    final paths = <String>[];

    // App bundle paths
    final executablePath = Platform.resolvedExecutable;
    final bundlePath = File(executablePath).parent.parent.path;
    paths.addAll([
      '$bundlePath/Frameworks/$dylibName',
      '$bundlePath/Resources/$dylibName',
    ]);

    // Development paths relative to current directory
    final currentDir = Directory.current.path;
    paths.addAll([
      '$currentDir/$dylibName',
      '$currentDir/build/$dylibName',
      '$currentDir/build/macos/$dylibName',
    ]);

    // System paths
    paths.addAll([
      '/usr/local/lib/$dylibName',
      '/opt/homebrew/lib/$dylibName',
    ]);

    return paths;
  }

  /// Load on Linux.
  static DynamicLibrary _loadLinux(String libraryName) {
    final soName = 'lib$libraryName.so';
    final paths = [
      soName,
      './$soName',
      '/usr/local/lib/$soName',
      '/usr/lib/$soName',
    ];

    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Try next path
      }
    }

    throw ArgumentError(
      'Could not load $soName on Linux. Tried: ${paths.join(", ")}',
    );
  }

  /// Load on Windows.
  static DynamicLibrary _loadWindows(String libraryName) {
    final dllName = '$libraryName.dll';
    final paths = [
      dllName,
      './$dllName',
    ];

    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Try next path
      }
    }

    throw ArgumentError(
      'Could not load $dllName on Windows. Tried: ${paths.join(", ")}',
    );
  }

  // =============================================================================
  // State and Utilities
  // =============================================================================

  /// Check if the commons library is loaded.
  static bool get isCommonsLoaded => _commonsLibrary != null;

  /// Check if the LlamaCPP library is loaded.
  static bool get isLlamaCppLoaded => _llamacppLibrary != null;

  /// Check if the ONNX library is loaded.
  static bool get isOnnxLoaded => _onnxLibrary != null;

  /// Legacy: Check if any native library is loaded.
  static bool get isLoaded => _commonsLibrary != null;

  /// Get the last load error, if any.
  static String? get loadError => _loadError;

  /// Unload all library references.
  ///
  /// Note: The actual libraries may remain in memory until process exit.
  static void unload() {
    _commonsLibrary = null;
    _llamacppLibrary = null;
    _onnxLibrary = null;
  }

  /// Get the current platform's library file extension.
  static String get libraryExtension {
    if (Platform.isAndroid || Platform.isLinux) return '.so';
    if (Platform.isIOS || Platform.isMacOS) return '.dylib';
    if (Platform.isWindows) return '.dll';
    return '';
  }

  /// Get the current platform's library file prefix.
  static String get libraryPrefix {
    if (Platform.isWindows) return '';
    return 'lib';
  }

  /// Check if native libraries are available on this platform.
  static bool get isAvailable {
    try {
      loadCommons();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Convenience alias for load().
  static DynamicLibrary loadNativeLibrary() => load();
}
