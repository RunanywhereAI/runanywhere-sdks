import 'dart:io';

/// SDK constants
///
/// Version constants must match:
/// - Swift SDK: Package.swift (commonsVersion, coreVersion)
/// - Kotlin SDK: build.gradle.kts (commonsVersion, coreVersion)
/// - React Native SDK: package.json (commonsVersion, coreVersion)
class SDKConstants {
  /// SDK version
  static const String version = '0.19.13';

  // ==========================================================================
  // Binary Version Constants
  // These MUST match the GitHub releases:
  // - RACommons: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/commons-v{commonsVersion}
  // - Backends: https://github.com/RunanywhereAI/runanywhere-binaries/releases/tag/core-v{coreVersion}
  // ==========================================================================

  /// RACommons version (core infrastructure)
  /// Source: https://github.com/RunanywhereAI/runanywhere-sdks/releases
  static const String commonsVersion = '0.1.6';

  /// RAC Core/Backends version (LlamaCPP, ONNX)
  /// Source: https://github.com/RunanywhereAI/runanywhere-binaries/releases
  static const String coreVersion = '0.1.6';

  /// Platform identifier
  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// SDK name
  static const String name = 'RunAnywhere Flutter SDK';

  /// User agent string
  /// Matches Swift: `"{name}/{version} (Swift)"` → here `"... (Flutter)"`.
  static String get userAgent => '$name/$version (Flutter)';

  /// Minimum log level in production (string form — mirrors Swift constant).
  static const String productionLogLevel = 'error';
}
