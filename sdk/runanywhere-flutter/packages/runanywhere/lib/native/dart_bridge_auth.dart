// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/dart_bridge_secure_storage.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// Secure Storage Callbacks
// =============================================================================

const int _exceptionalReturnInt = -333; // RAC_ERROR_SECURE_STORAGE_FAILED

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
/// - Synchronous platform-native secure storage callbacks
/// - Token resolver hooks that defer retry/auth work back to commons
class DartBridgeAuth {
  DartBridgeAuth._();

  static final _logger = SDKLogger('DartBridge.Auth');
  static final DartBridgeAuth instance = DartBridgeAuth._();

  static bool _isInitialized = false;

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
      // Resolve the synchronous helper before installing callbacks. Missing
      // native storage is an initialization error, not an in-memory fallback.
      DartBridgeSecureStorage.instance;

      final initAuth = lib
          .lookupFunction<
            Void Function(Pointer<RacSecureStorageCallbacksStruct>),
            void Function(Pointer<RacSecureStorageCallbacksStruct>)
          >('rac_auth_init');

      // Allocate and set up secure storage callbacks
      final storagePtr = calloc<RacSecureStorageCallbacksStruct>();
      storagePtr.ref.store = Pointer.fromFunction<RacSecureStoreCallbackNative>(
        _secureStoreCallback,
        _exceptionalReturnInt,
      );
      storagePtr.ref.retrieve =
          Pointer.fromFunction<RacSecureRetrieveCallbackNative>(
            _secureRetrieveCallback,
            _exceptionalReturnInt,
          );
      storagePtr.ref.deleteKey =
          Pointer.fromFunction<RacSecureDeleteCallbackNative>(
            _secureDeleteCallback,
            _exceptionalReturnInt,
          );
      storagePtr.ref.context = nullptr;

      // Commons copies the vtable, so the temporary struct can be released.
      try {
        initAuth(storagePtr);
      } finally {
        calloc.free(storagePtr);
      }

      final loadFn = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_auth_load_stored_tokens',
      );
      final loadResult = loadFn();
      if (loadResult != RacResultCode.success &&
          loadResult != RacResultCode.errorFileNotFound) {
        SDKException.throwIfError(loadResult);
      }

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
    } catch (_) {
      _isInitialized = false;
      _logger.error('Auth initialization failed');
      rethrow;
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
    } catch (_) {
      _logger.debug('Auth reset bridge unavailable');
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
    final lib = PlatformLoader.loadCommons();
    final clearFn = lib.lookupFunction<Int32 Function(), int Function()>(
      'rac_auth_clear',
    );
    SDKException.throwIfError(clearFn());
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

    return null;
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
    } catch (_) {
      _logger.debug('HTTP retry did not refresh auth');
      return null;
    }

    final fresh = getAccessToken();
    if (fresh != null && fresh.isNotEmpty) return fresh;
    return null;
  }
}

// =============================================================================
// Secure Storage Callbacks
// =============================================================================

/// Store callback
int _secureStoreCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> context,
) {
  if (key == nullptr || value == nullptr) {
    return RacResultCode.errorInvalidArgument;
  }

  try {
    return DartBridgeSecureStorage.instance.storePointers(key, value);
  } catch (_) {
    return RacResultCode.errorSecureStorageFailed;
  }
}

/// Retrieve callback
int _secureRetrieveCallback(
  Pointer<Utf8> key,
  Pointer<Utf8> outValue,
  int bufferSize,
  Pointer<Void> context,
) {
  if (key == nullptr || outValue == nullptr || bufferSize <= 0) {
    return RacResultCode.errorInvalidArgument;
  }

  try {
    return DartBridgeSecureStorage.instance.retrievePointers(
      key,
      outValue,
      bufferSize,
    );
  } catch (_) {
    return RacResultCode.errorSecureStorageFailed;
  }
}

/// Delete callback
int _secureDeleteCallback(Pointer<Utf8> key, Pointer<Void> context) {
  if (key == nullptr) return RacResultCode.errorInvalidArgument;

  try {
    return DartBridgeSecureStorage.instance.deletePointer(key);
  } catch (_) {
    return RacResultCode.errorSecureStorageFailed;
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
