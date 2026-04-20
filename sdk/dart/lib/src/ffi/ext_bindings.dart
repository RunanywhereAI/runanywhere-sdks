// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// FFI bindings for the v2 ABI extensions landed in Waves 3a/3b/3c/3d/3e:
// ra_auth_*, ra_telemetry_*, ra_model_*, ra_rag_*, ra_download_sha256_*.
// Complements `bindings.dart` (which covers pipeline / registry / plugin).

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Resolves the libracommons_core dynamic library on the current platform.
DynamicLibrary _openCore() {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS links statically into the app binary; executable()-based lookup
    // reaches the embedded symbols. macOS also accepts the dylib alongside.
    try {
      return DynamicLibrary.open('libracommons_core.dylib');
    } catch (_) {
      return DynamicLibrary.process();
    }
  }
  if (Platform.isAndroid) return DynamicLibrary.open('libracommons_core.so');
  if (Platform.isLinux)   return DynamicLibrary.open('libracommons_core.so');
  if (Platform.isWindows) return DynamicLibrary.open('racommons_core.dll');
  throw UnsupportedError('unsupported platform: ${Platform.operatingSystem}');
}

final DynamicLibrary _core = _openCore();

// =============================================================================
// Auth  (ra_auth.h)
// =============================================================================

typedef _AuthIsAuthC = Uint8 Function();
typedef _AuthIsAuth  = int  Function();
final _authIsAuth = _core.lookupFunction<_AuthIsAuthC, _AuthIsAuth>('ra_auth_is_authenticated');

typedef _AuthNeedsRefreshC = Uint8 Function(Int32);
typedef _AuthNeedsRefresh  = int   Function(int);
final _authNeedsRefresh = _core.lookupFunction<_AuthNeedsRefreshC, _AuthNeedsRefresh>('ra_auth_needs_refresh');

typedef _AuthGetStrC = Pointer<Utf8> Function();
typedef _AuthGetStr  = Pointer<Utf8> Function();
final _authGetAccess   = _core.lookupFunction<_AuthGetStrC, _AuthGetStr>('ra_auth_get_access_token');
final _authGetRefresh  = _core.lookupFunction<_AuthGetStrC, _AuthGetStr>('ra_auth_get_refresh_token');
final _authGetDeviceId = _core.lookupFunction<_AuthGetStrC, _AuthGetStr>('ra_auth_get_device_id');

typedef _AuthHandleResponseC = Int32 Function(Pointer<Utf8>);
typedef _AuthHandleResponse  = int   Function(Pointer<Utf8>);
final _authHandleAuthResp = _core.lookupFunction<_AuthHandleResponseC, _AuthHandleResponse>('ra_auth_handle_authenticate_response');
final _authHandleRefreshResp = _core.lookupFunction<_AuthHandleResponseC, _AuthHandleResponse>('ra_auth_handle_refresh_response');

typedef _VoidFn = Void Function();
final _authClear = _core.lookupFunction<_VoidFn, void Function()>('ra_auth_clear');

class Auth {
  static bool get isAuthenticated => _authIsAuth() != 0;
  static bool needsRefresh({int horizonSeconds = 60}) => _authNeedsRefresh(horizonSeconds) != 0;
  static String get accessToken  => _authGetAccess().toDartString();
  static String get refreshToken => _authGetRefresh().toDartString();
  static String get deviceId     => _authGetDeviceId().toDartString();

  static bool handleAuthenticateResponse(String body) =>
      _withCString(body, (p) => _authHandleAuthResp(p) == 0);

  static bool handleRefreshResponse(String body) =>
      _withCString(body, (p) => _authHandleRefreshResp(p) == 0);

  static void clear() => _authClear();
}

// =============================================================================
// Telemetry  (ra_telemetry.h)
// =============================================================================

typedef _TelemetryTrackC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _TelemetryTrack  = int   Function(Pointer<Utf8>, Pointer<Utf8>);
final _telemetryTrack = _core.lookupFunction<_TelemetryTrackC, _TelemetryTrack>('ra_telemetry_track');

typedef _TelemetryFlushC = Int32 Function();
typedef _TelemetryFlush  = int   Function();
final _telemetryFlush = _core.lookupFunction<_TelemetryFlushC, _TelemetryFlush>('ra_telemetry_flush');

typedef _PayloadDefaultC = Int32 Function(Pointer<Pointer<Utf8>>);
typedef _PayloadDefault  = int   Function(Pointer<Pointer<Utf8>>);
final _payloadDefault = _core.lookupFunction<_PayloadDefaultC, _PayloadDefault>('ra_telemetry_payload_default');

typedef _StringFreeC = Void Function(Pointer<Utf8>);
typedef _StringFree  = void Function(Pointer<Utf8>);
final _telemetryStringFree = _core.lookupFunction<_StringFreeC, _StringFree>('ra_telemetry_string_free');

class Telemetry {
  static bool track(String event, {String propertiesJson = '{}'}) =>
      _withTwoCStrings(event, propertiesJson, (a, b) => _telemetryTrack(a, b) == 0);

  static bool flush() => _telemetryFlush() == 0;

  static String defaultPayloadJson() {
    final out = calloc<Pointer<Utf8>>();
    try {
      if (_payloadDefault(out) != 0) return '{}';
      final str = out.value.toDartString();
      _telemetryStringFree(out.value);
      return str;
    } finally {
      calloc.free(out);
    }
  }
}

// =============================================================================
// Model helpers  (ra_model.h)
// =============================================================================

typedef _FwSupportsC = Uint8 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FwSupports  = int   Function(Pointer<Utf8>, Pointer<Utf8>);
final _fwSupports = _core.lookupFunction<_FwSupportsC, _FwSupports>('ra_framework_supports');

typedef _DetectFormatC = Int32 Function(Pointer<Utf8>);
typedef _DetectFormat  = int   Function(Pointer<Utf8>);
final _detectFormat   = _core.lookupFunction<_DetectFormatC, _DetectFormat>('ra_model_detect_format');
final _inferCategory  = _core.lookupFunction<_DetectFormatC, _DetectFormat>('ra_model_infer_category');

typedef _IsArchiveC = Uint8 Function(Pointer<Utf8>);
typedef _IsArchive  = int   Function(Pointer<Utf8>);
final _isArchive = _core.lookupFunction<_IsArchiveC, _IsArchive>('ra_artifact_is_archive');

class ModelHelpers {
  static bool frameworkSupports(String framework, String category) =>
      _withTwoCStrings(framework, category, (a, b) => _fwSupports(a, b) != 0);

  static int detectFormat(String urlOrPath) =>
      _withCString(urlOrPath, (p) => _detectFormat(p));

  static int inferCategory(String modelId) =>
      _withCString(modelId, (p) => _inferCategory(p));

  static bool isArchive(String urlOrPath) =>
      _withCString(urlOrPath, (p) => _isArchive(p) != 0);
}

// =============================================================================
// Download integrity  (ra_download.h)
// =============================================================================

typedef _Sha256FileC = Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _Sha256File  = int   Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
final _sha256File = _core.lookupFunction<_Sha256FileC, _Sha256File>('ra_download_sha256_file');

typedef _VerifySha256C = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _VerifySha256  = int   Function(Pointer<Utf8>, Pointer<Utf8>);
final _verifySha256 = _core.lookupFunction<_VerifySha256C, _VerifySha256>('ra_download_verify_sha256');

final _downloadStringFree = _core.lookupFunction<_StringFreeC, _StringFree>('ra_download_string_free');

class FileIntegrity {
  /// Returns the hex SHA-256 digest of the file, or null on I/O error.
  static String? sha256(String filePath) {
    final out = calloc<Pointer<Utf8>>();
    final p = filePath.toNativeUtf8();
    try {
      if (_sha256File(p, out) != 0) return null;
      final hex = out.value.toDartString();
      _downloadStringFree(out.value);
      return hex;
    } finally {
      calloc.free(p);
      calloc.free(out);
    }
  }

  /// Returns true iff `filePath` matches `expectedSha256Hex`.
  static bool verify(String filePath, String expectedSha256Hex) {
    final a = filePath.toNativeUtf8();
    final b = expectedSha256Hex.toNativeUtf8();
    try {
      return _verifySha256(a, b) == 0;
    } finally {
      calloc.free(a);
      calloc.free(b);
    }
  }
}

// =============================================================================
// Internal helpers
// =============================================================================

T _withCString<T>(String s, T Function(Pointer<Utf8>) f) {
  final p = s.toNativeUtf8();
  try { return f(p); } finally { calloc.free(p); }
}

T _withTwoCStrings<T>(String a, String b, T Function(Pointer<Utf8>, Pointer<Utf8>) f) {
  final pa = a.toNativeUtf8();
  final pb = b.toNativeUtf8();
  try { return f(pa, pb); } finally { calloc.free(pa); calloc.free(pb); }
}
