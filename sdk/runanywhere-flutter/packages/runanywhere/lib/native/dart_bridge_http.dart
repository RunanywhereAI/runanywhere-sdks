// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// HTTP Bridge
// =============================================================================

/// HTTP bridge - provides HTTP transport for C++ callbacks.
/// Matches Swift's `CppBridge+HTTP.swift` and `HTTPService.swift`.
///
/// This is the central HTTP transport layer that other bridges use.
/// C++ can request HTTP calls via callbacks, and this bridge executes them.
class DartBridgeHTTP {
  DartBridgeHTTP._();

  static final _logger = SDKLogger('DartBridge.HTTP');
  static final DartBridgeHTTP instance = DartBridgeHTTP._();

  String? _baseURL;
  String? _apiKey;
  String? _accessToken;
  final Map<String, String> _defaultHeaders = {};
  bool _isConfigured = false;

  /// Check if HTTP is configured
  bool get isConfigured => _isConfigured;

  /// Get base URL
  String? get baseURL => _baseURL;

  /// Configure HTTP settings
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

    // Configure in C++ layer if available
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

  /// Update access token
  void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Set API key
  void setApiKey(String key) {
    _apiKey = key;
  }

  /// Add default header
  void addHeader(String key, String value) {
    _defaultHeaders[key] = value;
  }

  /// Remove default header
  void removeHeader(String key) {
    _defaultHeaders.remove(key);
  }

  /// Get all default headers
  Map<String, String> get headers => Map.unmodifiable(_defaultHeaders);

  // ============================================================================
  // HTTP Methods
  // ============================================================================

  /// Perform GET request
  Future<HTTPResult> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    return _request(
      method: 'GET',
      endpoint: endpoint,
      headers: headers,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Perform POST request
  Future<HTTPResult> post(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    return _request(
      method: 'POST',
      endpoint: endpoint,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Perform PUT request
  Future<HTTPResult> put(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    return _request(
      method: 'PUT',
      endpoint: endpoint,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Perform DELETE request
  Future<HTTPResult> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    return _request(
      method: 'DELETE',
      endpoint: endpoint,
      headers: headers,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Internal request handler
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
      final url = Uri.parse('$_baseURL$endpoint');

      // Build headers
      final requestHeaders = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ..._defaultHeaders,
        if (headers != null) ...headers,
      };

      // Add auth header if required
      if (requiresAuth && _accessToken != null) {
        requestHeaders['Authorization'] = 'Bearer $_accessToken';
      } else if (requiresAuth && _apiKey != null) {
        requestHeaders['X-API-Key'] = _apiKey!;
      }

      // Encode body
      String? bodyString;
      if (body != null) {
        if (body is String) {
          bodyString = body;
        } else {
          bodyString = jsonEncode(body);
        }
      }

      // Make request with timeout
      final client = http.Client();
      http.Response response;

      try {
        final request = http.Request(method, url);
        request.headers.addAll(requestHeaders);
        if (bodyString != null) {
          request.body = bodyString;
        }

        final streamedResponse = await client
            .send(request)
            .timeout(timeout ?? const Duration(seconds: 30));
        response = await http.Response.fromStream(streamedResponse);
      } finally {
        client.close();
      }

      // Parse response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return HTTPResult.success(
          statusCode: response.statusCode,
          body: response.body,
          headers: response.headers,
        );
      } else {
        return HTTPResult(
          isSuccess: false,
          statusCode: response.statusCode,
          body: response.body,
          headers: response.headers,
          error: _parseError(response.body, response.statusCode),
        );
      }
    } catch (e) {
      _logger.error('HTTP request failed', metadata: {
        'method': method,
        'endpoint': endpoint,
        'error': e.toString(),
      });
      return HTTPResult.failure(e.toString());
    }
  }

  /// Download file
  Future<HTTPResult> download(
    String url,
    String destinationPath, {
    void Function(int downloaded, int total)? onProgress,
    Duration? timeout,
  }) async {
    try {
      final uri = url.startsWith('http') ? Uri.parse(url) : Uri.parse('$_baseURL$url');

      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        if (_accessToken != null) {
          request.headers['Authorization'] = 'Bearer $_accessToken';
        }

        final streamedResponse = await client.send(request);

        if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
          final file = await _saveStreamToFile(
            streamedResponse.stream,
            destinationPath,
            streamedResponse.contentLength ?? 0,
            onProgress,
          );

          return HTTPResult.success(
            statusCode: streamedResponse.statusCode,
            body: file,
          );
        } else {
          return HTTPResult(
            isSuccess: false,
            statusCode: streamedResponse.statusCode,
            error: 'Download failed with status ${streamedResponse.statusCode}',
          );
        }
      } finally {
        client.close();
      }
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

  Future<String> _saveStreamToFile(
    Stream<List<int>> stream,
    String path,
    int totalBytes,
    void Function(int, int)? onProgress,
  ) async {
    // Note: In a real implementation, use dart:io File to save
    // For now, just consume the stream
    var downloaded = 0;
    final chunks = <List<int>>[];

    await for (final chunk in stream) {
      chunks.add(chunk);
      downloaded += chunk.length;
      onProgress?.call(downloaded, totalBytes);
    }

    // Would save to file here
    return path;
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

  /// Parse JSON body
  Map<String, dynamic>? get json {
    if (body == null) return null;
    try {
      return jsonDecode(body!) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Parse JSON array body
  List<dynamic>? get jsonArray {
    if (body == null) return null;
    try {
      return jsonDecode(body!) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }
}
