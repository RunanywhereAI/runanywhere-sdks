import 'dart:ffi';
import 'dart:io';

/// Platform-specific library loader for RunAnywhere native libraries.
///
/// Supports:
/// - Android: Loads .so from jniLibs
/// - iOS: Uses DynamicLibrary.process() for statically linked XCFramework
/// - macOS: Loads .dylib for development/testing
class PlatformLoader {
  static DynamicLibrary? _library;
  static bool _isLoaded = false;
  static String? _loadError;

  /// The name of the native library (without platform-specific prefix/suffix)
  static const String _libraryName = 'runanywhere_bridge';

  /// Load the RunAnywhere native library for the current platform.
  ///
  /// Returns the loaded DynamicLibrary.
  /// Throws [UnsupportedError] if the platform is not supported.
  /// Throws [ArgumentError] if the library cannot be loaded.
  static DynamicLibrary load() {
    if (_isLoaded && _library != null) {
      return _library!;
    }

    try {
      _library = _loadPlatformLibrary();
      _isLoaded = true;
      _loadError = null;
      return _library!;
    } catch (e) {
      _loadError = e.toString();
      rethrow;
    }
  }

  /// Try to load the library, returning null if it fails.
  static DynamicLibrary? tryLoad() {
    try {
      return load();
    } catch (_) {
      return null;
    }
  }

  static DynamicLibrary _loadPlatformLibrary() {
    if (Platform.isAndroid) {
      return _loadAndroid();
    } else if (Platform.isIOS) {
      return _loadIOS();
    } else if (Platform.isMacOS) {
      return _loadMacOS();
    } else if (Platform.isLinux) {
      return _loadLinux();
    } else if (Platform.isWindows) {
      return _loadWindows();
    }

    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} is not supported. '
      'Supported platforms: Android, iOS, macOS, Linux, Windows.',
    );
  }

  /// Load on Android from jniLibs
  static DynamicLibrary _loadAndroid() {
    // First load dependencies in correct order for symbol visibility
    // These may already be loaded or bundled differently
    _tryLoadDependency('onnxruntime');
    _tryLoadDependency('sherpa-onnx-c-api');

    return DynamicLibrary.open('lib$_libraryName.so');
  }

  /// Load on iOS using process() for statically linked XCFramework
  static DynamicLibrary _loadIOS() {
    // iOS uses static linking via XCFramework in podspec
    // Symbols are already in the process
    return DynamicLibrary.process();
  }

  /// Load on macOS for development/testing
  static DynamicLibrary _loadMacOS() {
    // Try multiple possible locations for the dylib

    // 1. Check relative to the Flutter app bundle (for release builds)
    final executablePath = Platform.resolvedExecutable;
    final bundlePath = File(executablePath).parent.parent.path;
    final frameworkPaths = [
      '$bundlePath/Frameworks/lib$_libraryName.dylib',
      '$bundlePath/Resources/lib$_libraryName.dylib',
    ];

    for (final path in frameworkPaths) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }

    // 2. Check for library in Flutter SDK macos/Libraries/ directory
    final flutterSdkPaths = _getFlutterSdkLibraryPaths();
    for (final path in flutterSdkPaths) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }

    // 3. Check for local development build in runanywhere-core/build
    final devPaths = [
      // Direct path from runanywhere-core build output
      '${_getRunAnywhereCoreRoot()}/build/lib$_libraryName.dylib',
      '${_getRunAnywhereCoreRoot()}/build/Release/lib$_libraryName.dylib',
      '${_getRunAnywhereCoreRoot()}/build/macos/lib$_libraryName.dylib',
      '${_getRunAnywhereCoreRoot()}/build/macos-flutter/lib$_libraryName.dylib',
      // Relative paths for development
      '../../../runanywhere-core/build/lib$_libraryName.dylib',
      '../../../../runanywhere-core/build/lib$_libraryName.dylib',
    ];

    for (final path in devPaths) {
      final file = File(path);
      if (file.existsSync()) {
        return DynamicLibrary.open(file.absolute.path);
      }
    }

    // 4. Try system paths
    try {
      return DynamicLibrary.open('lib$_libraryName.dylib');
    } catch (_) {}

    // 5. Use process() as fallback (if statically linked)
    try {
      return DynamicLibrary.process();
    } catch (_) {}

    throw ArgumentError(
      'Could not load lib$_libraryName.dylib on macOS. '
      'Tried: ${[
        ...frameworkPaths,
        ...flutterSdkPaths,
        ...devPaths
      ].join(", ")}. '
      'Run: ./scripts/setup_native.sh --mode local --platform macos',
    );
  }

  /// Get paths to check in Flutter SDK macos/Libraries/ directory
  static List<String> _getFlutterSdkLibraryPaths() {
    final paths = <String>[];

    // Try to find the Flutter SDK path from current directory
    var dir = Directory.current;

    // Walk up looking for pubspec.yaml (Flutter package root)
    while (dir.path != dir.parent.path) {
      final pubspec = File('${dir.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        // Check if this is a Flutter package that depends on runanywhere
        final content = pubspec.readAsStringSync();
        if (content.contains('runanywhere')) {
          // Found a consuming app, look for the SDK
          final potentialPaths = [
            // For example app inside SDK
            '${dir.path}/../macos/Libraries/lib$_libraryName.dylib',
            // For external app with path dependency
            '${dir.path}/macos/.symlinks/plugins/runanywhere/macos/Libraries/lib$_libraryName.dylib',
          ];
          paths.addAll(potentialPaths);
        }

        // Check if this IS the runanywhere SDK
        if (content.contains('name: runanywhere')) {
          paths.add('${dir.path}/macos/Libraries/lib$_libraryName.dylib');
        }
        break;
      }
      dir = dir.parent;
    }

    return paths;
  }

  /// Load on Linux
  static DynamicLibrary _loadLinux() {
    // Similar search pattern to macOS
    final paths = [
      'lib$_libraryName.so',
      './lib$_libraryName.so',
      '/usr/local/lib/lib$_libraryName.so',
      '/usr/lib/lib$_libraryName.so',
    ];

    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {}
    }

    throw ArgumentError(
      'Could not load lib$_libraryName.so on Linux. '
      'Tried: ${paths.join(", ")}',
    );
  }

  /// Load on Windows
  static DynamicLibrary _loadWindows() {
    final paths = [
      '$_libraryName.dll',
      './$_libraryName.dll',
    ];

    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {}
    }

    throw ArgumentError(
      'Could not load $_libraryName.dll on Windows. '
      'Tried: ${paths.join(", ")}',
    );
  }

  /// Try to load a dependency library (for Android)
  static void _tryLoadDependency(String name) {
    try {
      DynamicLibrary.open('lib$name.so');
    } catch (_) {
      // Dependency may already be loaded or bundled differently
    }
  }

  /// Get the root path of runanywhere-core for development builds
  static String _getRunAnywhereCoreRoot() {
    // Try to find runanywhere-core relative to the Flutter SDK
    final currentDir = Directory.current.path;

    // If we're in the Flutter SDK directory structure
    if (currentDir.contains('runanywhere-flutter')) {
      // Navigate up to find runanywhere-core
      var dir = Directory(currentDir);
      while (dir.path != dir.parent.path) {
        final coreDir = Directory('${dir.path}/runanywhere-core');
        if (coreDir.existsSync()) {
          return coreDir.path;
        }
        // Also check sibling directories
        final siblingCore = Directory('${dir.parent.path}/runanywhere-core');
        if (siblingCore.existsSync()) {
          return siblingCore.path;
        }
        dir = dir.parent;
      }
    }

    // Fallback: use environment variable or return empty string
    return Platform.environment['RUNANYWHERE_CORE_ROOT'] ?? '';
  }

  /// Check if the native library is loaded.
  static bool get isLoaded => _isLoaded;

  /// Get the last load error, if any.
  static String? get loadError => _loadError;

  /// Unload the library reference (the actual library may remain in memory).
  static void unload() {
    _library = null;
    _isLoaded = false;
  }

  /// Get the current platform's library file extension
  static String get libraryExtension {
    if (Platform.isAndroid || Platform.isLinux) return '.so';
    if (Platform.isIOS || Platform.isMacOS) return '.dylib';
    if (Platform.isWindows) return '.dll';
    return '';
  }

  /// Get the current platform's library file prefix
  static String get libraryPrefix {
    if (Platform.isWindows) return '';
    return 'lib';
  }

  /// Get the full library filename for the current platform
  static String get libraryFilename =>
      '$libraryPrefix$_libraryName$libraryExtension';

  /// Convenience alias for load()
  static DynamicLibrary loadNativeLibrary() => load();
}
