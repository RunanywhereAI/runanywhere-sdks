import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' show Utf8Pointer;
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;

/// SDK constants
class SDKConstants {
  /// SDK version. Single source of truth is `sdk/runanywhere-commons/VERSION`,
  /// exposed through `rac_sdk_get_version()`, so the value reported here can
  /// never drift from the version commons reports in telemetry / auth headers.
  /// Mirrors Swift `SDKConstants.version` (SDKConstants.swift:14).
  static final String version = _nativeVersion;

  static String get _nativeVersion {
    final ptr = RacNative.bindings.rac_sdk_get_version();
    if (ptr == ffi.nullptr) {
      throw StateError('rac_sdk_get_version returned a null pointer');
    }
    final value = ptr.toDartString();
    if (value.isEmpty) {
      throw StateError('rac_sdk_get_version returned an empty version');
    }
    return value;
  }

  /// Platform identifier
  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// SDK name — matches Swift `SDKConstants.name` and Kotlin `SDK_NAME`.
  static const String name = 'RunAnywhere SDK';

  /// Minimum log level in production (string form — mirrors Swift constant).
  static const String productionLogLevel = 'error';
}
