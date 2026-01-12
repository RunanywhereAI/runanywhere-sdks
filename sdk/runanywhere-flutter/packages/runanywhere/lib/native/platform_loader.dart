import 'dart:ffi';
import 'dart:io';

/// Platform-specific library loader for RunAnywhere core native library (RACommons).
///
/// This loader is ONLY responsible for loading the core RACommons library.
/// Backend modules (LlamaCPP, ONNX, etc.) are responsible for loading their own
/// native libraries using their own loaders.
///
/// ## Architecture
/// - Core SDK (runanywhere) only knows about RACommons
/// - Backend modules are self-contained and handle their own native loading
/// - This separation ensures modularity and prevents tight coupling
///
/// ## iOS
/// XCFrameworks are statically linked into the app binary via CocoaPods.
/// Symbols are available via `DynamicLibrary.executable()` which can find
/// both global and local symbols in the main executable.
///
/// ## Android
/// .so files are loaded from jniLibs via `DynamicLibrary.open()`.
class PlatformLoader {
  // Cached library instance for RACommons
  static DynamicLibrary? _commonsLibrary;
  static String? _loadError;

  // Library name for RACommons (without platform-specific prefix/suffix)
  static const String _commonsLibraryName = 'rac_commons';

  // =============================================================================
  // Public API - RACommons Loading Only
  // =============================================================================

  /// Load the RACommons native library.
  ///
  /// This is the core library that provides:
  /// - Module registry
  /// - Service provider registry
  /// - Platform adapter interface
  /// - Logging and error handling
  /// - LLM/STT/TTS component APIs
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
  // Platform-Specific Loading (Internal)
  // =============================================================================

  /// Load a native library by name, using platform-appropriate method.
  ///
  /// This is exposed for backend modules to use if they want consistent
  /// platform handling, but modules can also implement their own loading.
  static DynamicLibrary loadLibrary(String libraryName) {
    return _loadLibrary(libraryName);
  }

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
  static DynamicLibrary _loadAndroid(String libraryName) {
    final soName = 'lib$libraryName.so';

    try {
      return DynamicLibrary.open(soName);
    } catch (e) {
      // Try JNI wrapper naming convention as fallback
      if (libraryName == 'rac_commons') {
        try {
          return DynamicLibrary.open('librunanywhere_jni.so');
        } catch (_) {
          // Fall through
        }
      }
      throw ArgumentError(
        'Could not load $soName on Android: $e. '
        'Ensure the native library is built and placed in jniLibs.',
      );
    }
  }

  /// Load on iOS using executable() for statically linked XCFramework.
  ///
  /// On iOS, all XCFrameworks (RACommons, RABackendLlamaCPP, RABackendONNX)
  /// are statically linked into the app binary via CocoaPods.
  ///
  /// IMPORTANT: We use DynamicLibrary.executable() instead of process() because:
  /// - process() uses dlsym(RTLD_DEFAULT) which only finds GLOBAL symbols
  /// - executable() can find both global and LOCAL symbols in the main binary
  /// - With static linkage, symbols from xcframeworks become local ('t' in nm)
  /// - This is the correct approach for statically linked Flutter plugins
  static DynamicLibrary _loadIOS(String libraryName) {
    return DynamicLibrary.executable();
  }

  /// Load on macOS for development/testing.
  static DynamicLibrary _loadMacOS(String libraryName) {
    // First try process() for statically linked builds (like iOS)
    try {
      final lib = DynamicLibrary.process();
      // Verify we can find rac_init (RACommons symbol)
      lib.lookup('rac_init');
      return lib;
    } catch (_) {
      // Fall through to dynamic loading
    }

    // Try executable() for statically linked builds
    try {
      final lib = DynamicLibrary.executable();
      lib.lookup('rac_init');
      return lib;
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

  /// Legacy: Check if any native library is loaded.
  static bool get isLoaded => _commonsLibrary != null;

  /// Get the last load error, if any.
  static String? get loadError => _loadError;

  /// Unload library reference.
  ///
  /// Note: The actual library may remain in memory until process exit.
  static void unload() {
    _commonsLibrary = null;
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
