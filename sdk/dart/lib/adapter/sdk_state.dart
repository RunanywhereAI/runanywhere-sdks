// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../src/ffi/primitive_bindings.dart';
import 'types.dart';

class AuthData {
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String userId;
  final String organizationId;
  final String deviceId;
  const AuthData({
    required this.accessToken,
    this.refreshToken = '',
    this.expiresAt = 0,
    this.userId = '',
    this.organizationId = '',
    this.deviceId = '',
  });
}

/// SDK-wide state: init, environment, API key, auth tokens, device
/// registration. Wraps ra_state_* / ra_init C ABI via FFI.
class SDKState {
  static RaPrimitiveBindings get _b => RaPrimitiveBindings.instance();

  static void initialize({
    required String apiKey,
    Environment environment = Environment.production,
    String baseUrl = '',
    String deviceId = '',
    LogLevel logLevel = LogLevel.info,
  }) {
    final keyPtr = apiKey.toNativeUtf8();
    final urlPtr = baseUrl.toNativeUtf8();
    final devPtr = deviceId.toNativeUtf8();
    try {
      final rc = _b.stateInitialize(environment.raw, keyPtr, urlPtr, devPtr);
      if (rc != 0) throw RunAnywhereException(rc, 'ra_state_initialize');
    } finally {
      calloc.free(keyPtr); calloc.free(urlPtr); calloc.free(devPtr);
    }
  }

  static bool get isInitialized => _b.stateIsInitialized() != 0;
  static void reset() => _b.stateReset();

  static Environment get environment => Environment.of(_b.stateGetEnvironment());
  static String get baseUrl  => _stringFrom(_b.stateGetBaseUrl());
  static String get apiKey   => _stringFrom(_b.stateGetApiKey());
  static String get deviceId => _stringFrom(_b.stateGetDeviceId());

  static void setAuth(AuthData auth) {
    final accessPtr = auth.accessToken.toNativeUtf8();
    final refreshPtr = auth.refreshToken.toNativeUtf8();
    final userPtr = auth.userId.toNativeUtf8();
    final orgPtr = auth.organizationId.toNativeUtf8();
    final devPtr = auth.deviceId.toNativeUtf8();
    final data = calloc<RaAuthData>();
    try {
      data.ref..accessToken = accessPtr..refreshToken = refreshPtr
        ..expiresAtUnix = auth.expiresAt..userId = userPtr
        ..organizationId = orgPtr..deviceId = devPtr;
      final rc = _b.stateSetAuth(data);
      if (rc != 0) throw RunAnywhereException(rc, 'ra_state_set_auth');
    } finally {
      calloc.free(data);
      calloc.free(accessPtr); calloc.free(refreshPtr);
      calloc.free(userPtr); calloc.free(orgPtr); calloc.free(devPtr);
    }
  }

  static String get accessToken    => _stringFrom(_b.stateGetAccessToken());
  static String get refreshToken   => _stringFrom(_b.stateGetRefreshToken());
  static String get userId         => _stringFrom(_b.stateGetUserId());
  static String get organizationId => _stringFrom(_b.stateGetOrganizationId());
  static bool   get isAuthenticated => _b.stateIsAuthenticated() != 0;
  static bool tokenNeedsRefresh({int horizonSeconds = 60}) =>
      _b.stateTokenNeedsRefresh(horizonSeconds) != 0;
  static int    get tokenExpiresAt => _b.stateGetTokenExpiresAt();
  static void clearAuth() => _b.stateClearAuth();

  static bool get isDeviceRegistered => _b.stateIsDeviceRegistered() != 0;
  static void setDeviceRegistered(bool registered) =>
      _b.stateSetDeviceRegistered(registered ? 1 : 0);

  static bool validateApiKey(String key) {
    final p = key.toNativeUtf8();
    try { return _b.stateValidateApiKey(p) != 0; }
    finally { calloc.free(p); }
  }

  static bool validateBaseUrl(String url) {
    final p = url.toNativeUtf8();
    try { return _b.stateValidateBaseUrl(p) != 0; }
    finally { calloc.free(p); }
  }

  static String _stringFrom(Pointer<Utf8> p) =>
      p == nullptr ? '' : p.toDartString();
}
