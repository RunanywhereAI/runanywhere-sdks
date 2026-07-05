// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// State bridge for C++ SDK state operations.
/// Matches Swift's `CppBridge+State.swift`.
///
/// Non-auth SDK state (environment, API key, base URL, device ID, device
/// registration flag) lives in rac_sdk_state. Auth state (tokens, user/org
/// IDs, expiry, refresh-window math, persistence) lives in rac_auth_manager
/// — auth accessors here delegate to rac_auth_* directly, matching the Swift
/// bridge pattern introduced in F3.
class DartBridgeState {
  DartBridgeState._();

  static final _logger = SDKLogger('DartBridge.State');
  static final DartBridgeState instance = DartBridgeState._();

  // Initialization

  /// Install auth secure storage after the platform async cache is ready.
  ///
  /// Phase 1 now drives `rac_sdk_init_phase1_proto` with environment, API key,
  /// base URL, device ID, platform, and SDK version. That commons call owns
  /// `rac_state_initialize`, so Flutter does not re-run state initialization in
  /// Phase 2. This method only wires the Keychain/KeyStore-backed auth vtable
  /// and restores any persisted auth tokens.
  ///
  Future<void> initialize({
    required SDKEnvironment environment,
    String? baseURL,
  }) async {
    try {
      await DartBridgeAuth.initialize(
        environment: environment,
        baseURL: baseURL,
      );

      _logger.debug('Auth secure storage initialized');
    } catch (e, stack) {
      _logger.debug(
        'Auth secure storage init error: $e',
        metadata: {'stack': stack.toString()},
      );
    }
  }

  /// Check if state is initialized
  bool get isInitialized {
    try {
      final lib = PlatformLoader.loadCommons();
      final isInit = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_state_is_initialized',
      );
      return isInit() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Reset state (for testing)
  void reset() {
    try {
      final lib = PlatformLoader.loadCommons();
      final resetState = lib.lookupFunction<Void Function(), void Function()>(
        'rac_state_reset',
      );
      resetState();
      // Also reset the auth manager so state/auth stay in sync.
      try {
        final resetAuth = lib.lookupFunction<Void Function(), void Function()>(
          'rac_auth_reset',
        );
        resetAuth();
      } catch (_) {
        // rac_auth_reset may not be linked yet; ignore.
      }
    } catch (e) {
      _logger.debug('rac_state_reset not available: $e');
    }
  }

  /// Shutdown state manager
  void shutdown() {
    try {
      final lib = PlatformLoader.loadCommons();
      final shutdownState = lib
          .lookupFunction<Void Function(), void Function()>(
            'rac_state_shutdown',
          );
      shutdownState();
      try {
        final resetAuth = lib.lookupFunction<Void Function(), void Function()>(
          'rac_auth_reset',
        );
        resetAuth();
      } catch (_) {
        // rac_auth_reset may not be linked yet; ignore.
      }
    } catch (e) {
      _logger.debug('rac_state_shutdown not available: $e');
    }
  }

  // Environment Queries

  /// Get current environment from C++ state
  SDKEnvironment get environment {
    try {
      final lib = PlatformLoader.loadCommons();
      final getEnv = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_state_get_environment',
      );
      return _intToEnvironment(getEnv());
    } catch (e) {
      return SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    }
  }

  /// Get base URL from C++ state
  String? get baseURL {
    try {
      final lib = PlatformLoader.loadCommons();
      final getBaseUrl = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_state_get_base_url',
          );

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
      final getApiKey = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_state_get_api_key',
          );

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
      final getDeviceId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_state_get_device_id',
          );

      final result = getDeviceId();
      if (result == nullptr) return null;
      final str = result.toDartString();
      return str.isEmpty ? null : str;
    } catch (e) {
      return null;
    }
  }

  // Auth State (delegated to rac_auth_manager)
  //
  // F3 removed rac_state_* auth symbols. All auth accessors now delegate to
  // rac_auth_* — single source of truth.

  /// Get access token from the auth manager
  String? get accessToken {
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

  /// Check if authenticated (valid non-expired token)
  bool get isAuthenticated {
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
  bool get tokenNeedsRefresh {
    try {
      final lib = PlatformLoader.loadCommons();
      final needsRefresh = lib.lookupFunction<Int32 Function(), int Function()>(
        'rac_auth_needs_refresh',
      );
      return needsRefresh() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Get user ID from the auth manager
  String? get userId {
    try {
      final lib = PlatformLoader.loadCommons();
      final getUserId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_user_id',
          );

      final result = getUserId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get organization ID from the auth manager
  String? get organizationId {
    try {
      final lib = PlatformLoader.loadCommons();
      final getOrgId = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'rac_auth_get_organization_id',
          );

      final result = getOrgId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Clear authentication state (in-memory + persisted).
  ///
  /// Delegates to `rac_auth_clear` which clears native auth state and the
  /// secure-storage vtable owned by `DartBridgeAuth`.
  Future<void> clearAuth() async {
    try {
      final lib = PlatformLoader.loadCommons();
      final clearAuthFn = lib.lookupFunction<Void Function(), void Function()>(
        'rac_auth_clear',
      );
      clearAuthFn();

      _logger.debug('Auth state cleared');
    } catch (e) {
      _logger.debug('Failed to clear auth: $e');
    }
  }

  // Device State

  /// Set device registration status
  void setDeviceRegistered(bool registered) {
    try {
      final lib = PlatformLoader.loadCommons();
      final setReg = lib
          .lookupFunction<Void Function(Int32), void Function(int)>(
            'rac_state_set_device_registered',
          );
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
        'rac_state_is_device_registered',
      );
      return isReg() != 0;
    } catch (e) {
      return false;
    }
  }

  // Helper Methods

  SDKEnvironment _intToEnvironment(int value) {
    switch (value) {
      case 0:
        return SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
      case 1:
        return SDKEnvironment.SDK_ENVIRONMENT_STAGING;
      case 2:
        return SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
      default:
        return SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    }
  }
}
