import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' show Utf8Pointer;
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;

/// SDK constants
class SDKConstants {
  /// SDK version. Single source of truth is `sdk/runanywhere-commons/VERSION`,
  /// exposed through `rac_sdk_get_version()`, so the value reported here can
  /// never drift from the version commons reports in telemetry / auth headers.
  /// Mirrors Swift `SDKConstants.version` (SDKConstants.swift:14). Falls back
  /// to the last-synced literal when the commons binary predates the export.
  static final String version = _nativeVersion ?? _fallbackVersion;

  static const String _fallbackVersion = '0.19.13';

  static String? get _nativeVersion {
    final fn = RacNative.bindings.rac_sdk_get_version;
    if (fn == null) return null;
    final ptr = fn();
    if (ptr == ffi.nullptr) return null;
    final value = ptr.toDartString();
    return value.isEmpty ? null : value;
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
