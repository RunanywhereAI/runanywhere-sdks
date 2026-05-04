// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// HTTP Bridge
// =============================================================================

/// HTTP bridge — provides HTTP transport for C++ callbacks.
/// Backed by the Phase H commons HTTP client (`rac_http_client_*`) via
/// [HTTPClientAdapter].
class DartBridgeHTTP {
  DartBridgeHTTP._();

  static final _logger = SDKLogger('DartBridge.HTTP');
  static final DartBridgeHTTP instance = DartBridgeHTTP._();

  String? _baseURL;
  String? _apiKey;
  String? _accessToken;
  final Map<String, String> _defaultHeaders = {};
  bool _isConfigured = false;

  bool get isConfigured => _isConfigured;

  String? get baseURL => _baseURL;

  Future<void> configure({
    required SDKEnvironment environment,
    String? apiKey,
    String? baseURL,
    String? accessToken,
    Map<String, String>? defaultHeaders,
  }) async {
    _apiKey = apiKey;
    _accessToken = accessToken;
    _baseURL = baseURL ?? _getDefaultBaseURL(environment);

    if (defaultHeaders != null) {
      _defaultHeaders.addAll(defaultHeaders);
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final configureFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_http_configure');

      final basePtr = (_baseURL ?? '').toNativeUtf8();
      final keyPtr = (_apiKey ?? '').toNativeUtf8();

      try {
        final result = configureFn(basePtr, keyPtr);
        if (result != RacResultCode.success) {
          _logger.warning('HTTP configure failed', metadata: {'code': result});
        }
      } finally {
        calloc.free(basePtr);
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_http_configure not available: $e');
    }

    _isConfigured = true;
    _logger.debug('HTTP configured', metadata: {'baseURL': _baseURL});
  }

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  void setApiKey(String key) {
    _apiKey = key;
  }

  void addHeader(String key, String value) {
    _defaultHeaders[key] = value;
  }

  void removeHeader(String key) {
    _defaultHeaders.remove(key);
  }

  Map<String, String> get headers => Map.unmodifiable(_defaultHeaders);

  // ============================================================================
  // HTTP Methods
  // ============================================================================

  Future<HTTPResult> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) =>
      _request(
        method: 'GET',
        endpoint: endpoint,
        headers: headers,
        requiresAuth: requiresAuth,
        timeout: timeout,
      );

  Future<HTTPResult> post(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) =>
      _request(
        method: 'POST',
        endpoint: endpoint,
        body: body,
        headers: headers,
        requiresAuth: requiresAuth,
        timeout: timeout,
      );

  Future<HTTPResult> put(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) =>
      _request(
        method: 'PUT',
        endpoint: endpoint,
        body: body,
        headers: headers,
        requiresAuth: requiresAuth,
        timeout: timeout,
      );

  Future<HTTPResult> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) =>
      _request(
        method: 'DELETE',
        endpoint: endpoint,
        headers: headers,
        requiresAuth: requiresAuth,
        timeout: timeout,
      );

  Future<HTTPResult> _request({
    required String method,
    required String endpoint,
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    if (!_isConfigured || _baseURL == null) {
      return HTTPResult.failure('HTTP not configured');
    }

    try {
      final url = '$_baseURL$endpoint';

      final requestHeaders = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ..._defaultHeaders,
        if (headers != null) ...headers,
      };

      if (requiresAuth) {
        final token = await _resolveToken(requiresAuth: true);
        if (token != null && token.isNotEmpty) {
          requestHeaders['Authorization'] = 'Bearer $token';
        } else if (_apiKey != null) {
          requestHeaders['X-API-Key'] = _apiKey!;
        }
      }

      Uint8List? bodyBytes;
      if (body != null) {
        if (body is String) {
          bodyBytes = Uint8List.fromList(utf8.encode(body));
        } else if (body is Uint8List) {
          bodyBytes = body;
        } else {
          bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
        }
      }

      final response = await HTTPClientAdapter.shared.rawRequest(
        method: method,
        url: url,
        headers: requestHeaders,
        body: bodyBytes,
        timeoutMs:
            (timeout ?? const Duration(seconds: 30)).inMilliseconds,
      );

      // 401-retry is owned by the C++ `auth_manager` — no Dart-side
      // refresh loop. Let the bearer token go stale and surface 401
      // to the caller; callers that care about refresh invoke
      // `DartBridgeAuth.refreshToken` directly.

      if (response.isSuccess) {
        return HTTPResult.success(
          statusCode: response.statusCode,
          body: response.body,
          headers: response.headers,
        );
      }
      return HTTPResult(
        isSuccess: false,
        statusCode: response.statusCode,
        body: response.body,
        headers: response.headers,
        error: _parseError(response.body, response.statusCode),
      );
    } catch (e) {
      _logger.error('HTTP request failed', metadata: {
        'method': method,
        'endpoint': endpoint,
        'error': e.toString(),
      });
      return HTTPResult.failure(e.toString());
    }
  }

  Future<String?> _resolveToken({required bool requiresAuth}) async {
    if (!requiresAuth) {
      return _apiKey;
    }

    final authBridge = DartBridgeAuth.instance;

    final currentToken = authBridge.getAccessToken();
    if (currentToken != null && !authBridge.needsRefresh()) {
      return currentToken;
    }

    if (authBridge.isAuthenticated()) {
      _logger.debug('Token needs refresh, attempting refresh...');
      final result = await authBridge.refreshToken();
      if (result.isSuccess) {
        final newToken = authBridge.getAccessToken();
        if (newToken != null) {
          _accessToken = newToken;
          _logger.info('Token refreshed successfully');
          return newToken;
        }
      } else {
        _logger.warning('Token refresh failed: ${result.error}');
      }
    }

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      return _accessToken;
    }
    return _apiKey;
  }

  /// Stream a file from [url] into [destinationPath]. On non-2xx
  /// responses the file is left untouched and a failure result is
  /// returned. `onProgress` is best-effort (the blocking request does
  /// not chunk-report; the hook is invoked with the final size when
  /// the download completes).
  Future<HTTPResult> download(
    String url,
    String destinationPath, {
    void Function(int downloaded, int total)? onProgress,
    Duration? timeout,
  }) async {
    try {
      final resolved = url.startsWith('http') ? url : '$_baseURL$url';
      final extraHeaders = <String, String>{};
      if (_accessToken != null) {
        extraHeaders['Authorization'] = 'Bearer $_accessToken';
      }

      final response = await HTTPClientAdapter.shared.rawRequest(
        method: 'GET',
        url: resolved,
        headers: extraHeaders,
        timeoutMs: (timeout ?? const Duration(seconds: 30)).inMilliseconds,
      );

      if (!response.isSuccess) {
        return HTTPResult(
          isSuccess: false,
          statusCode: response.statusCode,
          error: 'Download failed with status ${response.statusCode}',
        );
      }

      final file = File(destinationPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      onProgress?.call(response.bodyBytes.length, response.bodyBytes.length);

      return HTTPResult.success(
        statusCode: response.statusCode,
        body: destinationPath,
      );
    } catch (e) {
      return HTTPResult.failure(e.toString());
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  String _getDefaultBaseURL(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return 'https://dev-api.runanywhere.ai';
      case SDKEnvironment.staging:
        return 'https://staging-api.runanywhere.ai';
      case SDKEnvironment.production:
        return 'https://api.runanywhere.ai';
    }
  }

  String _parseError(String body, int statusCode) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['message'] as String? ??
          data['error'] as String? ??
          'HTTP error $statusCode';
    } catch (e) {
      return 'HTTP error $statusCode';
    }
  }
}

// =============================================================================
// HTTP Result
// =============================================================================

/// HTTP request result
class HTTPResult {
  final bool isSuccess;
  final int? statusCode;
  final String? body;
  final Map<String, String>? headers;
  final String? error;

  const HTTPResult({
    required this.isSuccess,
    this.statusCode,
    this.body,
    this.headers,
    this.error,
  });

  factory HTTPResult.success({
    required int statusCode,
    String? body,
    Map<String, String>? headers,
  }) =>
      HTTPResult(
        isSuccess: true,
        statusCode: statusCode,
        body: body,
        headers: headers,
      );

  factory HTTPResult.failure(String error) =>
      HTTPResult(isSuccess: false, error: error);

  Map<String, dynamic>? get json {
    if (body == null) return null;
    try {
      return jsonDecode(body!) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  List<dynamic>? get jsonArray {
    if (body == null) return null;
    try {
      return jsonDecode(body!) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }
}
