import 'dart:async';

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_platform.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// State bridge for C++ SDK state operations.
/// Matches Swift's `CppBridge+State.swift`.
///
/// C++ owns runtime state; Dart handles persistence (secure storage).
class DartBridgeState {
  DartBridgeState._();

  static final _logger = SDKLogger('DartBridge.State');
  static final DartBridgeState instance = DartBridgeState._();

  static bool _persistenceRegistered = false;

  /// Secure storage for token persistence
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Secure storage keys
  static const _keyAccessToken = 'com.runanywhere.sdk.accessToken';
  static const _keyRefreshToken = 'com.runanywhere.sdk.refreshToken';
  static const _keyDeviceId = 'com.runanywhere.sdk.deviceId';
  static const _keyUserId = 'com.runanywhere.sdk.userId';
  static const _keyOrganizationId = 'com.runanywhere.sdk.organizationId';

  // ============================================================================
  // Initialization
  // ============================================================================

  /// Initialize C++ state manager
  Future<void> initialize({
    required SDKEnvironment environment,
    String? apiKey,
    String? baseURL,
    String? deviceId,
  }) async {
    try {
      final lib = PlatformLoader.loadCommons();

      // First load secure storage cache for platform adapter
      await loadSecureStorageCache();

      // Initialize state
      final initState = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(int, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_state_initialize');

      final envValue = _environmentToInt(environment);
      final apiKeyPtr = (apiKey ?? '').toNativeUtf8();
      final baseURLPtr = (baseURL ?? '').toNativeUtf8();
      final deviceIdPtr = (deviceId ?? '').toNativeUtf8();

      try {
        final result = initState(envValue, apiKeyPtr, baseURLPtr, deviceIdPtr);
        if (result != RacResultCode.success) {
          _logger.warning('State init failed', metadata: {'code': result});
        }
      } finally {
        calloc.free(apiKeyPtr);
        calloc.free(baseURLPtr);
        calloc.free(deviceIdPtr);
      }

      // Register persistence callbacks
      _registerPersistenceCallbacks();

      // Load stored auth from secure storage into C++ state
      await _loadStoredAuth();

      _logger.debug('C++ state initialized');
    } catch (e, stack) {
      _logger.debug('rac_state_initialize error: $e', metadata: {
        'stack': stack.toString(),
      });
    }
  }

  /// Check if state is initialized
  bool get isInitialized {
    try {
      final lib = PlatformLoader.loadCommons();
      final isInit = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_is_initialized');
      return isInit() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Reset state (for testing)
  void reset() {
    try {
      final lib = PlatformLoader.loadCommons();
      final resetState = lib
          .lookupFunction<Void Function(), void Function()>('rac_state_reset');
      resetState();
    } catch (e) {
      _logger.debug('rac_state_reset not available: $e');
    }
  }

  /// Shutdown state manager
  void shutdown() {
    try {
      final lib = PlatformLoader.loadCommons();
      final shutdownState =
          lib.lookupFunction<Void Function(), void Function()>(
              'rac_state_shutdown');
      shutdownState();
      _persistenceRegistered = false;
    } catch (e) {
      _logger.debug('rac_state_shutdown not available: $e');
    }
  }

  // ============================================================================
  // Environment Queries
  // ============================================================================

  /// Get current environment from C++ state
  SDKEnvironment get environment {
    try {
      final lib = PlatformLoader.loadCommons();
      final getEnv = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_get_environment');
      return _intToEnvironment(getEnv());
    } catch (e) {
      return SDKEnvironment.development;
    }
  }

  /// Get base URL from C++ state
  String? get baseURL {
    try {
      final lib = PlatformLoader.loadCommons();
      final getBaseUrl = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_base_url');

      final result = getBaseUrl();
      if (result == nullptr) return null;
      final str = result.toDartString();
      return str.isEmpty ? null : str;
    } catch (e) {
      return null;
    }
  }

  /// Get API key from C++ state
  String? get apiKey {
    try {
      final lib = PlatformLoader.loadCommons();
      final getApiKey = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_api_key');

      final result = getApiKey();
      if (result == nullptr) return null;
      final str = result.toDartString();
      return str.isEmpty ? null : str;
    } catch (e) {
      return null;
    }
  }

  /// Get device ID from C++ state
  String? get deviceId {
    try {
      final lib = PlatformLoader.loadCommons();
      final getDeviceId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_device_id');

      final result = getDeviceId();
      if (result == nullptr) return null;
      final str = result.toDartString();
      return str.isEmpty ? null : str;
    } catch (e) {
      return null;
    }
  }

  // ============================================================================
  // Auth State
  // ============================================================================

  /// Set authentication state after successful HTTP auth
  Future<void> setAuth({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
    String? userId,
    required String organizationId,
    required String deviceId,
  }) async {
    try {
      final lib = PlatformLoader.loadCommons();
      final setAuth = lib.lookupFunction<
          Int32 Function(Pointer<RacAuthDataStruct>),
          int Function(Pointer<RacAuthDataStruct>)>('rac_state_set_auth');

      final expiresAtUnix = expiresAt.millisecondsSinceEpoch ~/ 1000;

      final accessTokenPtr = accessToken.toNativeUtf8();
      final refreshTokenPtr = refreshToken.toNativeUtf8();
      final userIdPtr = userId?.toNativeUtf8() ?? nullptr;
      final organizationIdPtr = organizationId.toNativeUtf8();
      final deviceIdPtr = deviceId.toNativeUtf8();

      final authData = calloc<RacAuthDataStruct>();

      try {
        authData.ref.accessToken = accessTokenPtr;
        authData.ref.refreshToken = refreshTokenPtr;
        authData.ref.expiresAtUnix = expiresAtUnix;
        authData.ref.userId = userIdPtr;
        authData.ref.organizationId = organizationIdPtr;
        authData.ref.deviceId = deviceIdPtr;

        final result = setAuth(authData);
        if (result != RacResultCode.success) {
          _logger
              .warning('Failed to set auth state', metadata: {'code': result});
        }
      } finally {
        calloc.free(accessTokenPtr);
        calloc.free(refreshTokenPtr);
        if (userIdPtr != nullptr) calloc.free(userIdPtr);
        calloc.free(organizationIdPtr);
        calloc.free(deviceIdPtr);
        calloc.free(authData);
      }

      // Also store in secure storage
      await _storeTokensInSecureStorage(
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
        userId: userId,
        organizationId: organizationId,
      );

      _logger.debug('Auth state set in C++');
    } catch (e) {
      _logger.debug('rac_state_set_auth error: $e');
    }
  }

  /// Get access token from C++ state
  String? get accessToken {
    try {
      final lib = PlatformLoader.loadCommons();
      final getToken = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_access_token');

      final result = getToken();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get refresh token from C++ state
  String? get refreshToken {
    try {
      final lib = PlatformLoader.loadCommons();
      final getToken = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_refresh_token');

      final result = getToken();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Check if authenticated (valid non-expired token)
  bool get isAuthenticated {
    try {
      final lib = PlatformLoader.loadCommons();
      final isAuth = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_is_authenticated');
      return isAuth() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Check if token needs refresh
  bool get tokenNeedsRefresh {
    try {
      final lib = PlatformLoader.loadCommons();
      final needsRefresh = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_token_needs_refresh');
      return needsRefresh() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Get token expiry timestamp
  DateTime? get tokenExpiresAt {
    try {
      final lib = PlatformLoader.loadCommons();
      final getExpiry = lib.lookupFunction<Int64 Function(), int Function()>(
          'rac_state_get_token_expires_at');

      final unix = getExpiry();
      return unix > 0 ? DateTime.fromMillisecondsSinceEpoch(unix * 1000) : null;
    } catch (e) {
      return null;
    }
  }

  /// Get user ID from C++ state
  String? get userId {
    try {
      final lib = PlatformLoader.loadCommons();
      final getUserId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_user_id');

      final result = getUserId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get organization ID from C++ state
  String? get organizationId {
    try {
      final lib = PlatformLoader.loadCommons();
      final getOrgId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_state_get_organization_id');

      final result = getOrgId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Clear authentication state
  Future<void> clearAuth() async {
    try {
      final lib = PlatformLoader.loadCommons();
      final clearAuthFn = lib.lookupFunction<Void Function(), void Function()>(
          'rac_state_clear_auth');
      clearAuthFn();

      // Clear from secure storage too
      await _secureStorage.delete(key: _keyAccessToken);
      await _secureStorage.delete(key: _keyRefreshToken);
      await _secureStorage.delete(key: _keyDeviceId);
      await _secureStorage.delete(key: _keyUserId);
      await _secureStorage.delete(key: _keyOrganizationId);

      _logger.debug('Auth state cleared');
    } catch (e) {
      _logger.debug('Failed to clear auth: $e');
    }
  }

  // ============================================================================
  // Device State
  // ============================================================================

  /// Set device registration status
  void setDeviceRegistered(bool registered) {
    try {
      final lib = PlatformLoader.loadCommons();
      final setReg =
          lib.lookupFunction<Void Function(Int32), void Function(int)>(
              'rac_state_set_device_registered');
      setReg(registered ? 1 : 0);
    } catch (e) {
      _logger.debug('rac_state_set_device_registered not available: $e');
    }
  }

  /// Check if device is registered
  bool get isDeviceRegistered {
    try {
      final lib = PlatformLoader.loadCommons();
      final isReg = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_is_device_registered');
      return isReg() != 0;
    } catch (e) {
      return false;
    }
  }

  // ============================================================================
  // Persistence (Secure Storage Integration)
  // ============================================================================

  /// Register Keychain/secure storage persistence callbacks with C++
  void _registerPersistenceCallbacks() {
    if (_persistenceRegistered) return;

    // Note: C++ expects synchronous callbacks, so we use the cache from platform adapter
    // The platform adapter handles the async-to-sync bridging

    _persistenceRegistered = true;
    _logger.debug('Persistence callbacks registered');
  }

  /// Load stored auth from secure storage into C++ state
  Future<void> _loadStoredAuth() async {
    try {
      final accessToken = await _secureStorage.read(key: _keyAccessToken);
      final refreshToken = await _secureStorage.read(key: _keyRefreshToken);

      if (accessToken == null || refreshToken == null) {
        _logger.debug('No stored auth data found');
        return;
      }

      final userId = await _secureStorage.read(key: _keyUserId);
      final orgId = await _secureStorage.read(key: _keyOrganizationId);
      final deviceIdStored = await _secureStorage.read(key: _keyDeviceId);

      // Set in C++ state with unknown expiry (will be checked via API)
      await setAuth(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt:
            DateTime.now().add(const Duration(hours: 1)), // Default expiry
        userId: userId,
        organizationId: orgId ?? '',
        deviceId: deviceIdStored ?? '',
      );

      _logger.debug('Loaded stored auth from secure storage');
    } catch (e) {
      _logger.debug('Error loading stored auth: $e');
    }
  }

  /// Store tokens in secure storage
  Future<void> _storeTokensInSecureStorage({
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    String? userId,
    required String organizationId,
  }) async {
    try {
      await _secureStorage.write(key: _keyAccessToken, value: accessToken);
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
      await _secureStorage.write(key: _keyDeviceId, value: deviceId);
      if (userId != null) {
        await _secureStorage.write(key: _keyUserId, value: userId);
      }
      await _secureStorage.write(
          key: _keyOrganizationId, value: organizationId);
    } catch (e) {
      _logger.debug('Error storing tokens: $e');
    }
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  int _environmentToInt(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.development:
        return 0;
      case SDKEnvironment.staging:
        return 1;
      case SDKEnvironment.production:
        return 2;
    }
  }

  SDKEnvironment _intToEnvironment(int value) {
    switch (value) {
      case 0:
        return SDKEnvironment.development;
      case 1:
        return SDKEnvironment.staging;
      case 2:
        return SDKEnvironment.production;
      default:
        return SDKEnvironment.development;
    }
  }
}

// =============================================================================
// Auth Data Struct (matches rac_auth_data_t)
// =============================================================================

/// Auth data struct for C++ interop
base class RacAuthDataStruct extends Struct {
  external Pointer<Utf8> accessToken;
  external Pointer<Utf8> refreshToken;

  @Int64()
  external int expiresAtUnix;

  external Pointer<Utf8> userId;
  external Pointer<Utf8> organizationId;
  external Pointer<Utf8> deviceId;
}
