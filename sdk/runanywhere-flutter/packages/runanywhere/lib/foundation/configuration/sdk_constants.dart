import 'dart:io';

/// SDK constants
class SDKConstants {
  /// SDK version
  static const String version = '0.15.8';

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
}
