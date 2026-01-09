// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../foundation/logging/sdk_logger.dart';
import '../public/configuration/sdk_environment.dart';
import 'dart_bridge_state.dart';
import 'platform_loader.dart';

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
/// - HTTP transport for auth requests
class DartBridgeAuth {
  DartBridgeAuth._();

  static final _logger = SDKLogger('DartBridge.Auth');
  static final DartBridgeAuth instance = DartBridgeAuth._();

  static bool _isInitialized = false;
  static String? _baseURL;
  static SDKEnvironment _environment = SDKEnvironment.development;

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

    _environment = environment;
    _baseURL = baseURL;

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate and set up secure storage callbacks
      _storagePtr = calloc<RacSecureStorageCallbacksStruct>();
      _storagePtr!.ref.store =
          Pointer.fromFunction<RacSecureStoreCallbackNative>(
              _secureStoreCallback, _exceptionalReturnInt);
      _storagePtr!.ref.retrieve =
          Pointer.fromFunction<RacSecureRetrieveCallbackNative>(
              _secureRetrieveCallback, _exceptionalReturnInt);
      _storagePtr!.ref.deleteKey =
          Pointer.fromFunction<RacSecureDeleteCallbackNative>(
              _secureDeleteCallback, _exceptionalReturnInt);
      _storagePtr!.ref.context = nullptr;

      // Initialize auth with storage
      final initAuth = lib.lookupFunction<
          Void Function(Pointer<RacSecureStorageCallbacksStruct>),
          void Function(
              Pointer<RacSecureStorageCallbacksStruct>)>('rac_auth_init');

      initAuth(_storagePtr!);

      // Load stored tokens
      instance._loadStoredTokens();

      _isInitialized = true;
      _logger.debug('Auth manager initialized');
    } catch (e, stack) {
      _logger.debug('Auth initialization error: $e', metadata: {
        'stack': stack.toString(),
      });
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Reset auth manager
  static void reset() {
    try {
      final lib = PlatformLoader.loadCommons();
      final resetFn =
          lib.lookupFunction<Void Function(), void Function()>('rac_auth_reset');
      resetFn();
    } catch (e) {
      _logger.debug('rac_auth_reset not available: $e');
    }
  }

  // ============================================================================
  // Authentication Flow
  // ============================================================================

  /// Authenticate with API key
  /// Returns auth response with tokens
  Future<AuthResult> authenticate({
    required String apiKey,
    required String deviceId,
    String? buildToken,
  }) async {
    try {
      // Build authenticate request JSON via C++
      final requestJson = _buildAuthenticateRequestJSON(
        apiKey: apiKey,
        deviceId: deviceId,
        buildToken: buildToken,
      );

      if (requestJson == null) {
        return AuthResult.failure('Failed to build auth request');
      }

      // Make HTTP request
      final endpoint = _getAuthEndpoint();
      final baseURL = _baseURL ?? _getDefaultBaseURL();
      final url = Uri.parse('$baseURL$endpoint');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: requestJson,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response via C++
        final success = _handleAuthenticateResponse(response.body);
        if (success) {
          return AuthResult.success(_parseAuthResponse(response.body));
        } else {
          return AuthResult.failure('Failed to parse auth response');
        }
      } else {
        // Parse API error
        final errorMsg = _parseAPIError(response.body, response.statusCode);
        return AuthResult.failure(errorMsg);
      }
    } catch (e) {
      _logger.error('Authentication error', metadata: {'error': e.toString()});
      return AuthResult.failure(e.toString());
    }
  }

  /// Refresh access token
  Future<AuthResult> refreshToken() async {
    try {
      // Build refresh request JSON via C++
      final requestJson = _buildRefreshRequestJSON();

      if (requestJson == null) {
        return AuthResult.failure('No refresh token available');
      }

      // Make HTTP request
      final endpoint = _getRefreshEndpoint();
      final baseURL = _baseURL ?? _getDefaultBaseURL();
      final url = Uri.parse('$baseURL$endpoint');

      // Get current token for auth header
      final currentToken = getAccessToken();

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (currentToken != null) {
        headers['Authorization'] = 'Bearer $currentToken';
      }

      final response = await http.post(url, headers: headers, body: requestJson);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final success = _handleRefreshResponse(response.body);
        if (success) {
          return AuthResult.success(_parseAuthResponse(response.body));
        } else {
          return AuthResult.failure('Failed to parse refresh response');
        }
      } else {
        final errorMsg = _parseAPIError(response.body, response.statusCode);
        return AuthResult.failure(errorMsg);
      }
    } catch (e) {
      _logger.error('Token refresh error', metadata: {'error': e.toString()});
      return AuthResult.failure(e.toString());
    }
  }

  /// Get valid access token, refreshing if needed
  Future<String?> getValidToken() async {
    if (!isAuthenticated()) {
      return null;
    }

    if (needsRefresh()) {
      _logger.debug('Token needs refresh');
      final result = await refreshToken();
      if (!result.isSuccess) {
        _logger.warning('Token refresh failed', metadata: {'error': result.error});
        return null;
      }
    }

    return getAccessToken();
  }

  /// Clear all auth state
  Future<void> clearAuth() async {
    try {
      final lib = PlatformLoader.loadCommons();
      final clearFn =
          lib.lookupFunction<Void Function(), void Function()>('rac_auth_clear');
      clearFn();

      // Also clear via state bridge
      await DartBridgeState.instance.clearAuth();
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
          'rac_auth_is_authenticated');
      return isAuth() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Check if token needs refresh
  bool needsRefresh() {
    try {
      final lib = PlatformLoader.loadCommons();
      final needsRefreshFn = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_auth_needs_refresh');
      return needsRefreshFn() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Get current access token
  String? getAccessToken() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getToken = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_get_access_token');

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
      final getId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_get_device_id');

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
      final getId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_get_user_id');

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
      final getId = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_get_organization_id');

      final result = getId();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  /// Build authenticate request JSON via C++
  String? _buildAuthenticateRequestJSON({
    required String apiKey,
    required String deviceId,
    String? buildToken,
  }) {
    try {
      final lib = PlatformLoader.loadCommons();
      final buildRequest = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<RacSdkConfigStruct>),
          Pointer<Utf8> Function(
              Pointer<RacSdkConfigStruct>)>('rac_auth_build_authenticate_request');

      final config = calloc<RacSdkConfigStruct>();
      final apiKeyPtr = apiKey.toNativeUtf8();
      final deviceIdPtr = deviceId.toNativeUtf8();
      final buildTokenPtr = buildToken?.toNativeUtf8() ?? nullptr;

      try {
        config.ref.apiKey = apiKeyPtr;
        config.ref.deviceId = deviceIdPtr;
        config.ref.buildToken = buildTokenPtr.cast<Utf8>();

        final result = buildRequest(config);
        if (result == nullptr) return null;

        final json = result.toDartString();

        // Free C++ allocated string
        final freeFn = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('rac_free');
        freeFn(result.cast<Void>());

        return json;
      } finally {
        calloc.free(apiKeyPtr);
        calloc.free(deviceIdPtr);
        if (buildTokenPtr != nullptr) calloc.free(buildTokenPtr);
        calloc.free(config);
      }
    } catch (e) {
      _logger.debug('rac_auth_build_authenticate_request error: $e');
      // Fallback: build JSON manually
      return jsonEncode({
        'apiKey': apiKey,
        'deviceId': deviceId,
        if (buildToken != null) 'buildToken': buildToken,
      });
    }
  }

  /// Build refresh request JSON via C++
  String? _buildRefreshRequestJSON() {
    try {
      final lib = PlatformLoader.loadCommons();
      final buildRequest = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_build_refresh_request');

      final result = buildRequest();
      if (result == nullptr) return null;

      final json = result.toDartString();

      // Free C++ allocated string
      final freeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');
      freeFn(result.cast<Void>());

      return json;
    } catch (e) {
      _logger.debug('rac_auth_build_refresh_request error: $e');
      return null;
    }
  }

  /// Handle authenticate response via C++
  bool _handleAuthenticateResponse(String json) {
    try {
      final lib = PlatformLoader.loadCommons();
      final handleResponse = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_auth_handle_authenticate_response');

      final jsonPtr = json.toNativeUtf8();
      try {
        final result = handleResponse(jsonPtr);
        return result == 0;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      _logger.debug('rac_auth_handle_authenticate_response error: $e');
      return false;
    }
  }

  /// Handle refresh response via C++
  bool _handleRefreshResponse(String json) {
    try {
      final lib = PlatformLoader.loadCommons();
      final handleResponse = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_auth_handle_refresh_response');

      final jsonPtr = json.toNativeUtf8();
      try {
        final result = handleResponse(jsonPtr);
        return result == 0;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      _logger.debug('rac_auth_handle_refresh_response error: $e');
      return false;
    }
  }

  /// Parse auth response for return value
  AuthData _parseAuthResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return AuthData(
        accessToken: data['accessToken'] as String? ?? data['access_token'] as String?,
        refreshToken: data['refreshToken'] as String? ?? data['refresh_token'] as String?,
        deviceId: data['deviceId'] as String? ?? data['device_id'] as String?,
        userId: data['userId'] as String? ?? data['user_id'] as String?,
        organizationId:
            data['organizationId'] as String? ?? data['organization_id'] as String?,
        expiresAt: data['expiresAt'] as int? ?? data['expires_at'] as int?,
      );
    } catch (e) {
      return const AuthData();
    }
  }

  /// Parse API error response
  String _parseAPIError(String json, int statusCode) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final message = data['message'] as String? ??
          data['error'] as String? ??
          'Unknown error';
      return '$message (HTTP $statusCode)';
    } catch (e) {
      return 'HTTP error $statusCode';
    }
  }

  /// Load stored tokens from secure storage
  void _loadStoredTokens() {
    try {
      final lib = PlatformLoader.loadCommons();
      final loadFn = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_auth_load_stored_tokens');
      loadFn();
    } catch (e) {
      _logger.debug('rac_auth_load_stored_tokens error: $e');
    }
  }

  String _getAuthEndpoint() {
    return '/api/v1/auth/sdk/authenticate';
  }

  String _getRefreshEndpoint() {
    return '/api/v1/auth/sdk/refresh';
  }

  String _getDefaultBaseURL() {
    switch (_environment) {
      case SDKEnvironment.development:
        return 'https://dev-api.runanywhere.ai';
      case SDKEnvironment.staging:
        return 'https://staging-api.runanywhere.ai';
      case SDKEnvironment.production:
        return 'https://api.runanywhere.ai';
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
    Pointer<Utf8> key, Pointer<Utf8> value, Pointer<Void> context) {
  if (key == nullptr || value == nullptr) return -1;

  try {
    final keyStr = key.toDartString();
    final valueStr = value.toDartString();

    // Update cache
    _secureCache[keyStr] = valueStr;

    // Schedule async write
    _writeToSecureStorage(keyStr, valueStr);

    return 0;
  } catch (e) {
    return -1;
  }
}

/// Retrieve callback
int _secureRetrieveCallback(
    Pointer<Utf8> key, Pointer<Utf8> outValue, int bufferSize, Pointer<Void> context) {
  if (key == nullptr || outValue == nullptr) return -1;

  try {
    final keyStr = key.toDartString();
    final value = _secureCache[keyStr];

    if (value == null) return -1;

    // Copy to output buffer
    final bytes = value.codeUnits;
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

    // Schedule async delete
    _deleteFromSecureStorage(keyStr);

    return 0;
  } catch (e) {
    return -1;
  }
}

/// Async write to secure storage
Future<void> _writeToSecureStorage(String key, String value) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
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
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
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
typedef RacSecureStoreCallbackNative = Int32 Function(
    Pointer<Utf8> key, Pointer<Utf8> value, Pointer<Void> context);

/// Secure storage retrieve callback
typedef RacSecureRetrieveCallbackNative = Int32 Function(
    Pointer<Utf8> key, Pointer<Utf8> outValue, IntPtr bufferSize, Pointer<Void> context);

/// Secure storage delete callback
typedef RacSecureDeleteCallbackNative = Int32 Function(
    Pointer<Utf8> key, Pointer<Void> context);

/// Secure storage callbacks struct
base class RacSecureStorageCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacSecureStoreCallbackNative>> store;
  external Pointer<NativeFunction<RacSecureRetrieveCallbackNative>> retrieve;
  external Pointer<NativeFunction<RacSecureDeleteCallbackNative>> deleteKey;
  external Pointer<Void> context;
}

/// SDK config struct for auth requests
base class RacSdkConfigStruct extends Struct {
  external Pointer<Utf8> apiKey;
  external Pointer<Utf8> deviceId;
  external Pointer<Utf8> buildToken;
}

// =============================================================================
// Result Types
// =============================================================================

/// Authentication result
class AuthResult {
  final bool isSuccess;
  final AuthData? data;
  final String? error;

  const AuthResult._({
    required this.isSuccess,
    this.data,
    this.error,
  });

  factory AuthResult.success(AuthData data) =>
      AuthResult._(isSuccess: true, data: data);

  factory AuthResult.failure(String error) =>
      AuthResult._(isSuccess: false, error: error);
}

/// Authentication data
class AuthData {
  final String? accessToken;
  final String? refreshToken;
  final String? deviceId;
  final String? userId;
  final String? organizationId;
  final int? expiresAt;

  const AuthData({
    this.accessToken,
    this.refreshToken,
    this.deviceId,
    this.userId,
    this.organizationId,
    this.expiresAt,
  });
}
