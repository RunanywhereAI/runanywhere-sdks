// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// Secure Storage Callbacks
// =============================================================================

const int _exceptionalReturnInt = -1;

// =============================================================================
// Auth Manager Bridge
// =============================================================================

/// Authentication bridge for C++ auth operations.
/// Matches Swift's `CppBridge+Auth.swift`.
///
/// C++ handles:
/// - Token expiry/refresh logic
/// - JSON building for auth requests
/// - Auth state management
///
/// Dart provides:
/// - Secure storage (via flutter_secure_storage)
/// - Token resolver hooks that defer retry/auth work back to commons
class DartBridgeAuth {
  DartBridgeAuth._();

  static final _logger = SDKLogger('DartBridge.Auth');
  static final DartBridgeAuth instance = DartBridgeAuth._();

  static bool _isInitialized = false;

  /// Secure storage callbacks pointer
  static Pointer<RacSecureStorageCallbacksStruct>? _storagePtr;

  // ============================================================================
  // Initialization
  // ============================================================================

  /// Initialize auth manager with secure storage callbacks
  static Future<void> initialize({
    required SDKEnvironment environment,
    String? baseURL,
  }) async {
    if (_isInitialized) return;

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate and set up secure storage callbacks
      _storagePtr = calloc<RacSecureStorageCallbacksStruct>();
      _storagePtr!.ref.store =
          Pointer.fromFunction<RacSecureStoreCallbackNative>(
            _secureStoreCallback,
            _exceptionalReturnInt,
          );
      _storagePtr!.ref.retrieve =
          Pointer.fromFunction<RacSecureRetrieveCallbackNative>(
            _secureRetrieveCallback,
            _exceptionalReturnInt,
          );
      _storagePtr!.ref.deleteKey =
          Pointer.fromFunction<RacSecureDeleteCallbackNative>(
            _secureDeleteCallback,
            _exceptionalReturnInt,
          );
      _storagePtr!.ref.context = nullptr;

      // Initialize auth with storage
      final initAuth = lib
          .lookupFunction<
            Void Function(Pointer<RacSecureStorageCallbacksStruct>),
            void Function(Pointer<RacSecureStorageCallbacksStruct>)
          >('rac_auth_init');

      initAuth(_storagePtr!);

      // Load stored tokens
      await instance._loadStoredTokens();

      // Wire token refresh hooks into the shared HTTP client so any
      // request with `requiresAuth: true` can pick up / refresh tokens
      // without a direct dependency on this bridge.
      HTTPClientAdapter.shared.setTokenResolver(instance._resolveToken);
      HTTPClientAdapter.shared.setRefreshCallback(instance._refreshForAdapter);

      _isInitialized = true;
      _logger.debug(
        'Auth manager initialized',
        metadata: {
          'environment': environment.toString(),
          'hasBaseURL': '${baseURL != null && baseURL.isNotEmpty}',
        },
      );
    } catch (e, stack) {
      _logger.debug(
        'Auth initialization error: $e',
        metadata: {'stack': stack.toString()},
      );
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Reset auth manager
  static void reset() {
    try {
      final lib = PlatformLoader.loadCommons();
      final resetFn = lib.lookupFunction<Void Function(), void Function()>(
        'rac_auth_reset',
      );
      resetFn();
    } catch (e) {
      _logger.debug('rac_auth_reset not available: $e');
    }
    // Mirror Swift CppBridge.State.shutdown() which resets authStorageInstalled
    // so that a subsequent initialize() re-wires the secure-storage vtable.
    // Without this, initialize()'s early-return guard fires and token
    // persistence silently breaks on logout→login re-init flows.
    _isInitialized = false;
  }

  // ============================================================================
  // Authentication Flow
  // ============================================================================

  /// Auth request construction, HTTP POSTs, response parsing, and token refresh
  /// are owned by commons via `rac_sdk_init_phase2_proto` and
  /// `rac_sdk_retry_http_proto`. Dart only installs secure-storage callbacks
  /// and reads the resulting native auth state.

  /// Clear all auth state (in-memory + persisted via the secure-storage
  /// vtable installed at `rac_auth_init`). Delegates fully to the native
  /// auth manager — matches Swift `CppBridge.State.clearAuth`.
  Future<void> clearAuth() async {
    try {
      final lib = PlatformLoader.loadCommons();
      final clearFn = lib.lookupFunction<Void Function(), void Function()>(
        'rac_auth_clear',
      );
      clearFn();
    } catch (e) {
      _logger.debug('rac_auth_clear not available: $e');
    }
  }

  // ============================================================================
  // Token Accessors
  // ============================================================================

  /// Check if authenticated
  bool isAuthenticated() {
    try {
      final lib = PlatformLoader.loadCommons();
      final isAuth = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_auth_is_authenticated',
      );
      return isAuth() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Check if token needs refresh
  bool needsRefresh() {
    try {
      final lib = PlatformLoader.loadCommons();
      final needsRefreshFn = lib
          .lookupFunction<Int32 Function(), int Function()>(
            'rac_auth_needs_refresh',
          );
      return needsRefreshFn() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Get current access token
  String? getAccessToken() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getToken = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_access_token',
          );

      final result = getToken();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get device ID
  String? getDeviceId() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_device_id',
          );

      final result = getId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get user ID
  String? getUserId() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_user_id',
          );

      final result = getId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get organization ID
  String? getOrganizationId() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_organization_id',
          );

      final result = getId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  // ============================================================================
  // HTTP Client Integration
  // ============================================================================

  /// Token resolver consumed by [HTTPClientAdapter] to attach a valid
  /// bearer on `requiresAuth: true` requests. Returns null when no
  /// token is available (adapter falls back to API key).
  Future<String?> _resolveToken({required bool requiresAuth}) async {
    if (!requiresAuth) return null;

    final current = getAccessToken();
    if (current != null && current.isNotEmpty && !needsRefresh()) {
      return current;
    }

    final refreshed = await _retryHTTPViaCommons();
    if (refreshed != null && refreshed.isNotEmpty) return refreshed;

    // A proactive refresh just failed (init race / transient network). Prefer a
    // still-usable live token over giving up — returning empty here makes the
    // adapter fall back to `Bearer <apiKey>`, which is a guaranteed 401 on the
    // JWT-only V2 telemetry endpoints. The adapter's 401-retry path
    // (_refreshForAdapter) still handles the case where this token is truly
    // expired, so we never strand an auth'd request that had a valid token.
    if (current != null && current.isNotEmpty) return current;

    // Last-resort cached access token (may still be stale; the server
    // will reject it and the 401 retry path will refresh again).
    return _secureCache['com.runanywhere.sdk.accessToken'];
  }

  /// Adapter-facing refresh hook. Returns the new access token, or
  /// null if the refresh attempt failed.
  Future<String?> _refreshForAdapter() async {
    return _retryHTTPViaCommons();
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  Future<String?> _retryHTTPViaCommons() async {
    try {
      final result = DartBridgeSdkInit.retryHTTP();
      if (!result.success) return null;
    } catch (e) {
      _logger.debug('rac_sdk_retry_http_proto did not refresh auth: $e');
      return null;
    }

    final fresh = getAccessToken();
    if (fresh != null && fresh.isNotEmpty) return fresh;
    return _secureCache['com.runanywhere.sdk.accessToken'];
  }

  /// Load stored tokens from secure storage
  Future<void> _loadStoredTokens() async {
    // Try C++ method first
    try {
      final lib = PlatformLoader.loadCommons();
      final loadFn = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_auth_load_stored_tokens',
      );
      loadFn();
    } catch (e) {
      _logger.debug('rac_auth_load_stored_tokens not available: $e');
    }

    // Also pre-load tokens into cache from Flutter secure storage
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

      final accessToken = await storage.read(
        key: 'com.runanywhere.sdk.accessToken',
      );
      final refreshToken = await storage.read(
        key: 'com.runanywhere.sdk.refreshToken',
      );
      final deviceId = await storage.read(key: 'com.runanywhere.sdk.deviceId');
      final userId = await storage.read(key: 'com.runanywhere.sdk.userId');
      final organizationId = await storage.read(
        key: 'com.runanywhere.sdk.organizationId',
      );

      if (accessToken != null) {
        _secureCache['com.runanywhere.sdk.accessToken'] = accessToken;
      }
      if (refreshToken != null) {
        _secureCache['com.runanywhere.sdk.refreshToken'] = refreshToken;
      }
      if (deviceId != null) {
        _secureCache['com.runanywhere.sdk.deviceId'] = deviceId;
      }
      if (userId != null) {
        _secureCache['com.runanywhere.sdk.userId'] = userId;
      }
      if (organizationId != null) {
        _secureCache['com.runanywhere.sdk.organizationId'] = organizationId;
      }

      _logger.debug(
        'Loaded tokens from secure storage',
        metadata: {
          'hasAccessToken': accessToken != null,
          'hasRefreshToken': refreshToken != null,
          'hasDeviceId': deviceId != null,
        },
      );
    } catch (e) {
      _logger.debug('Failed to pre-load tokens from secure storage: $e');
    }
  }
}

// =============================================================================
// Secure Storage Callbacks
// =============================================================================

/// Cached secure storage values for sync access
final Map<String, String> _secureCache = {};

/// Store callback
int _secureStoreCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> context,
) {
  if (key == nullptr || value == nullptr) return -1;

  try {
    final keyStr = key.toDartString();
    final valueStr = value.toDartString();

    // Update cache
    _secureCache[keyStr] = valueStr;

    // Schedule async write (fire-and-forget, cache is authoritative)
    unawaited(_writeToSecureStorage(keyStr, valueStr));

    return 0;
  } catch (e) {
    return -1;
  }
}

/// Retrieve callback
int _secureRetrieveCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> outValue,
  int bufferSize,
  Pointer<Void> context,
) {
  if (key == nullptr || outValue == nullptr) return -1;

  try {
    final keyStr = key.toDartString();
    final value = _secureCache[keyStr];

    if (value == null) return -1;

    // Copy UTF-8 bytes into the caller buffer. `codeUnits` emits UTF-16 code
    // units and silently mangles any non-ASCII secret; `utf8.encode` matches
    // the Swift bridge, which copies `value.utf8CString`.
    final bytes = utf8.encode(value);
    final maxLen = bufferSize - 1; // Leave room for null terminator

    if (bytes.length > maxLen) {
      return -1; // Buffer too small
    }

    final outPtr = outValue.cast<Uint8>();
    for (var i = 0; i < bytes.length; i++) {
      outPtr[i] = bytes[i];
    }
    outPtr[bytes.length] = 0; // Null terminator

    return bytes.length;
  } catch (e) {
    return -1;
  }
}

/// Delete callback
int _secureDeleteCallback(Pointer<Utf8> key, Pointer<Void> context) {
  if (key == nullptr) return -1;

  try {
    final keyStr = key.toDartString();

    // Update cache
    _secureCache.remove(keyStr);

    // Schedule async delete (fire-and-forget, cache is authoritative)
    unawaited(_deleteFromSecureStorage(keyStr));

    return 0;
  } catch (e) {
    return -1;
  }
}

/// Async write to secure storage
Future<void> _writeToSecureStorage(String key, String value) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    await storage.write(key: key, value: value);
  } catch (e) {
    // Ignore - cache is authoritative
  }
}

/// Async delete from secure storage
Future<void> _deleteFromSecureStorage(String key) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    await storage.delete(key: key);
  } catch (e) {
    // Ignore
  }
}

// =============================================================================
// FFI Types
// =============================================================================

/// Secure storage store callback
typedef RacSecureStoreCallbackNative =
    Int32 Function(
      Pointer<Utf8> key,
      Pointer<Utf8> value,
      Pointer<Void> context,
    );

/// Secure storage retrieve callback
typedef RacSecureRetrieveCallbackNative =
    Int32 Function(
      Pointer<Utf8> key,
      Pointer<Utf8> outValue,
      IntPtr bufferSize,
      Pointer<Void> context,
    );

/// Secure storage delete callback
typedef RacSecureDeleteCallbackNative =
    Int32 Function(Pointer<Utf8> key, Pointer<Void> context);

/// Secure storage callbacks struct
base class RacSecureStorageCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacSecureStoreCallbackNative>> store;
  external Pointer<NativeFunction<RacSecureRetrieveCallbackNative>> retrieve;
  external Pointer<NativeFunction<RacSecureDeleteCallbackNative>> deleteKey;
  external Pointer<Void> context;
}
