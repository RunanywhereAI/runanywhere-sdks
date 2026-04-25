// SPDX-License-Identifier: Apache-2.0
//
// http_client_adapter.dart — thin Dart wrapper around the Phase H
// commons HTTP client C ABI (`rac_http_client_*`,
// `rac_http_request_send`). Replaces the per-SDK libcurl / URLSession
// / HttpURLConnection transports (`HTTPService`, `APIClient`).
//
// Design:
//   * Single curl-backed client handle, created lazily and destroyed
//     on `shutdown()`.
//   * Each `request()` runs on a background isolate via `Isolate.run`
//     so the blocking libcurl call never stalls the UI thread.
//   * The adapter carries the SDK-level request config (baseURL,
//     apiKey, env, access token, default headers) so call sites don't
//     have to reconstruct `Authorization` / `apikey` / `Prefer` headers
//     themselves.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Minimal response container, platform-agnostic.
class HttpClientResponse {
  HttpClientResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    this.elapsedMs = 0,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final int elapsedMs;

  /// Lazily-decoded UTF-8 body. Safe on binary payloads (returns
  /// replacement chars), but callers that need bytes should use
  /// [bodyBytes] directly.
  String get body => utf8.decode(bodyBytes, allowMalformed: true);

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Immutable config snapshot shipped to the worker isolate for each
/// request. Keeps the adapter thread-safe.
class _HttpRequestSpec {
  const _HttpRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.timeoutMs,
    required this.followRedirects,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final Uint8List? body;
  final int timeoutMs;
  final bool followRedirects;
}

class _HttpRequestResult {
  const _HttpRequestResult({
    required this.rc,
    required this.status,
    required this.headers,
    required this.body,
    required this.elapsedMs,
  });

  final int rc;
  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  final int elapsedMs;
}

/// High-level HTTP client shared across the Flutter SDK.
///
/// Usage:
/// ```dart
/// HTTPClientAdapter.shared.configure(
///   baseURL: 'https://api.runanywhere.ai',
///   apiKey: '...',
///   environment: SDKEnvironment.production,
/// );
/// final resp = await HTTPClientAdapter.shared.post(
///   '/api/v1/devices/register',
///   body: {'device_id': 'abc'},
/// );
/// ```
class HTTPClientAdapter {
  HTTPClientAdapter._();

  static final HTTPClientAdapter shared = HTTPClientAdapter._();

  static const int defaultTimeoutMs = 30000;

  final SDKLogger _logger = SDKLogger('HTTPClientAdapter');

  String _baseURL = '';
  String _apiKey = '';
  SDKEnvironment _environment = SDKEnvironment.production;
  String? _accessToken;
  int _timeoutMs = defaultTimeoutMs;

  // Development (Supabase) overrides.
  String _supabaseURL = '';
  String _supabaseKey = '';

  // Per-request token resolver (injected by auth bridge to avoid a
  // cyclic import between this adapter and DartBridgeAuth).
  Future<String?> Function({required bool requiresAuth})? _tokenResolver;
  Future<String?> Function()? _refreshTokenCallback;

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------

  void configure({
    required String baseURL,
    required String apiKey,
    SDKEnvironment environment = SDKEnvironment.production,
    int timeoutMs = defaultTimeoutMs,
  }) {
    _baseURL = baseURL;
    _apiKey = apiKey;
    _environment = environment;
    _timeoutMs = timeoutMs;
    _logger.info(
      'Configured for ${environment.name} environment: ${_hostname(baseURL)}',
    );
  }

  void configureDev({required String supabaseURL, required String supabaseKey}) {
    _supabaseURL = supabaseURL;
    _supabaseKey = supabaseKey;
    _logger.info('Dev mode configured with Supabase');
  }

  void setToken(String? token) {
    _accessToken = token;
  }

  String? get accessToken => _accessToken;

  String get baseURL => _supabaseURL.isNotEmpty &&
          _environment == SDKEnvironment.development
      ? _supabaseURL
      : _baseURL;

  SDKEnvironment get environment => _environment;

  String get apiKey => _apiKey;

  String get supabaseKey => _supabaseKey;

  bool get isConfigured {
    if (_environment == SDKEnvironment.development) {
      return _supabaseURL.isNotEmpty;
    }
    return _baseURL.isNotEmpty;
  }

  /// Wire in a token resolver so `requiresAuth: true` requests can
  /// trigger token refresh without this adapter importing the auth
  /// bridge directly.
  void setTokenResolver(
    Future<String?> Function({required bool requiresAuth}) resolver,
  ) {
    _tokenResolver = resolver;
  }

  /// Hook invoked after a 401 to let the auth bridge refresh the
  /// token and return a new one.
  void setRefreshCallback(Future<String?> Function() onRefresh) {
    _refreshTokenCallback = onRefresh;
  }

  // --------------------------------------------------------------------------
  // Public request API
  // --------------------------------------------------------------------------

  /// Low-level raw request. Caller owns URL + headers + body.
  Future<HttpClientResponse> rawRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    Uint8List? body,
    int? timeoutMs,
    bool followRedirects = true,
  }) async {
    final spec = _HttpRequestSpec(
      method: method.toUpperCase(),
      url: url,
      headers: headers ?? const <String, String>{},
      body: body,
      timeoutMs: timeoutMs ?? _timeoutMs,
      followRedirects: followRedirects,
    );
    _logger.debug('${spec.method} ${spec.url}');
    final res = await Isolate.run<_HttpRequestResult>(() => _sendBlocking(spec));
    if (res.rc != 0) {
      throw HttpClientException(
        'rac_http_request_send failed with code ${res.rc}',
        statusCode: res.status,
      );
    }
    return HttpClientResponse(
      statusCode: res.status,
      headers: res.headers,
      bodyBytes: res.body,
      elapsedMs: res.elapsedMs,
    );
  }

  /// Send a request resolving SDK URL / auth / default header rules.
  Future<HttpClientResponse> send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
    bool requiresAuth = false,
    int? timeoutMs,
    bool followRedirects = true,
  }) async {
    if (!isConfigured) {
      throw HttpClientException('HTTPClientAdapter not configured');
    }

    final url = _buildFullURL(path);
    final resolvedHeaders = await _buildHeaders(
      path: path,
      extra: headers,
      requiresAuth: requiresAuth,
    );
    final encodedBody = _encodeBody(body);

    var response = await rawRequest(
      method: method,
      url: _maybeAppendSupabaseUpsert(url, path),
      headers: resolvedHeaders,
      body: encodedBody,
      timeoutMs: timeoutMs,
      followRedirects: followRedirects,
    );

    // Retry-once on 401 after a token refresh.
    if (response.statusCode == 401 &&
        requiresAuth &&
        _refreshTokenCallback != null) {
      try {
        final newToken = await _refreshTokenCallback!.call();
        if (newToken != null && newToken.isNotEmpty) {
          _accessToken = newToken;
          final retryHeaders = Map<String, String>.from(resolvedHeaders);
          retryHeaders['Authorization'] = 'Bearer $newToken';
          response = await rawRequest(
            method: method,
            url: _maybeAppendSupabaseUpsert(url, path),
            headers: retryHeaders,
            body: encodedBody,
            timeoutMs: timeoutMs,
            followRedirects: followRedirects,
          );
        }
      } catch (e) {
        _logger.warning('Token refresh failed: $e');
      }
    }

    return response;
  }

  Future<HttpClientResponse> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
    int? timeoutMs,
  }) =>
      send(
        method: 'POST',
        path: path,
        body: body,
        headers: headers,
        requiresAuth: requiresAuth,
        timeoutMs: timeoutMs,
      );

  Future<HttpClientResponse> get(
    String path, {
    Map<String, String>? headers,
    bool requiresAuth = false,
    int? timeoutMs,
  }) =>
      send(
        method: 'GET',
        path: path,
        headers: headers,
        requiresAuth: requiresAuth,
        timeoutMs: timeoutMs,
      );

  Future<HttpClientResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
    int? timeoutMs,
  }) =>
      send(
        method: 'PUT',
        path: path,
        body: body,
        headers: headers,
        requiresAuth: requiresAuth,
        timeoutMs: timeoutMs,
      );

  Future<HttpClientResponse> delete(
    String path, {
    Map<String, String>? headers,
    bool requiresAuth = false,
    int? timeoutMs,
  }) =>
      send(
        method: 'DELETE',
        path: path,
        headers: headers,
        requiresAuth: requiresAuth,
        timeoutMs: timeoutMs,
      );

  /// Reset for testing — clears config + token resolver hooks.
  void resetForTesting() {
    _baseURL = '';
    _apiKey = '';
    _environment = SDKEnvironment.production;
    _accessToken = null;
    _timeoutMs = defaultTimeoutMs;
    _supabaseURL = '';
    _supabaseKey = '';
    _tokenResolver = null;
    _refreshTokenCallback = null;
  }

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  String _buildFullURL(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = baseURL.endsWith('/')
        ? baseURL.substring(0, baseURL.length - 1)
        : baseURL;
    final endpoint = path.startsWith('/') ? path : '/$path';
    return '$base$endpoint';
  }

  /// Supabase device-registration endpoints need `on_conflict=device_id`
  /// to do an UPSERT instead of rejecting duplicates.
  String _maybeAppendSupabaseUpsert(String url, String path) {
    if (_environment != SDKEnvironment.development) return url;
    if (!_isDeviceRegistrationPath(path)) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}on_conflict=device_id';
  }

  bool _isDeviceRegistrationPath(String path) {
    return path.contains('sdk_devices') ||
        path.contains('devices/register') ||
        path.contains('rest/v1/sdk_devices');
  }

  Future<Map<String, String>> _buildHeaders({
    required String path,
    required Map<String, String>? extra,
    required bool requiresAuth,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-SDK-Client': 'RunAnywhereFlutterSDK',
      'X-SDK-Version': SDKConstants.version,
      'X-Platform': SDKConstants.platform,
    };

    if (_environment == SDKEnvironment.development) {
      if (_supabaseKey.isNotEmpty) {
        headers['apikey'] = _supabaseKey;
        headers['Authorization'] = 'Bearer $_supabaseKey';
        headers['Prefer'] = _isDeviceRegistrationPath(path)
            ? 'resolution=merge-duplicates'
            : 'return=representation';
      }
    } else {
      if (requiresAuth && _tokenResolver != null) {
        try {
          final token = await _tokenResolver!.call(requiresAuth: true);
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          } else if (_apiKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer $_apiKey';
          }
        } catch (e) {
          _logger.debug('Token resolver failed: $e');
          if (_apiKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer $_apiKey';
          }
        }
      } else {
        final token = _accessToken ?? _apiKey;
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      if (_apiKey.isNotEmpty) {
        headers['apikey'] = _apiKey;
      }
    }

    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Uint8List? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is Uint8List) return body;
    if (body is String) return Uint8List.fromList(utf8.encode(body));
    if (body is List<int>) return Uint8List.fromList(body);
    // Map / List / toJson object — JSON-encode.
    try {
      final jsonable = (body is Map || body is List)
          ? body
          : (body as dynamic).toJson();
      return Uint8List.fromList(utf8.encode(json.encode(jsonable)));
    } catch (_) {
      throw ArgumentError(
          'HTTPClientAdapter: unsupported body type ${body.runtimeType}');
    }
  }

  String _hostname(String url) {
    final match = RegExp(r'^https?://([^/:]+)').firstMatch(url);
    return match != null
        ? match.group(1)!
        : url.substring(0, url.length.clamp(0, 30));
  }
}

/// Thrown when the underlying libcurl call fails before we have a
/// server status (DNS, TLS, connect, cancel, etc.) or when the caller
/// has not configured the adapter yet.
class HttpClientException implements Exception {
  HttpClientException(this.message, {this.statusCode = 0});
  final String message;
  final int statusCode;

  @override
  String toString() => 'HttpClientException($statusCode): $message';
}

// ============================================================================
// Blocking FFI worker (runs on helper isolate)
// ============================================================================

_HttpRequestResult _sendBlocking(_HttpRequestSpec spec) {
  final bindings = RacNative.bindings;

  final clientOut = calloc<ffi.Pointer<ffi.Void>>();
  final createRc = bindings.rac_http_client_create(clientOut);
  if (createRc != 0 || clientOut.value == ffi.nullptr) {
    calloc.free(clientOut);
    return _HttpRequestResult(
      rc: createRc != 0 ? createRc : -1,
      status: 0,
      headers: const <String, String>{},
      body: Uint8List(0),
      elapsedMs: 0,
    );
  }
  final client = clientOut.value;
  calloc.free(clientOut);

  final methodPtr = spec.method.toNativeUtf8();
  final urlPtr = spec.url.toNativeUtf8();

  final headerEntries = spec.headers.entries.toList();
  final headerArray = headerEntries.isEmpty
      ? ffi.nullptr.cast<RacHttpHeaderKv>()
      : calloc<RacHttpHeaderKv>(headerEntries.length);
  final headerNamePtrs = <ffi.Pointer<Utf8>>[];
  final headerValuePtrs = <ffi.Pointer<Utf8>>[];
  for (var i = 0; i < headerEntries.length; i++) {
    final kv = headerEntries[i];
    final namePtr = kv.key.toNativeUtf8();
    final valPtr = kv.value.toNativeUtf8();
    headerNamePtrs.add(namePtr);
    headerValuePtrs.add(valPtr);
    headerArray[i]
      ..name = namePtr
      ..value = valPtr;
  }

  final body = spec.body;
  final bodyLen = body?.length ?? 0;
  final bodyPtr = bodyLen == 0
      ? ffi.nullptr.cast<ffi.Uint8>()
      : calloc<ffi.Uint8>(bodyLen);
  if (bodyLen > 0 && body != null) {
    bodyPtr.asTypedList(bodyLen).setAll(0, body);
  }

  final reqPtr = calloc<RacHttpRequest>();
  reqPtr.ref
    ..method = methodPtr
    ..url = urlPtr
    ..headers = headerArray
    ..headerCount = headerEntries.length
    ..bodyBytes = bodyPtr
    ..bodyLen = bodyLen
    ..timeoutMs = spec.timeoutMs
    ..followRedirects = spec.followRedirects ? 1 : 0
    ..expectedChecksumHex = ffi.nullptr.cast<Utf8>();

  final respPtr = calloc<RacHttpResponse>();

  int rc;
  int status = 0;
  var headers = const <String, String>{};
  var bodyBytes = Uint8List(0);
  int elapsedMs = 0;
  try {
    rc = bindings.rac_http_request_send(client, reqPtr, respPtr);
    if (rc == 0) {
      final ref = respPtr.ref;
      status = ref.status;
      elapsedMs = ref.elapsedMs;
      if (ref.bodyBytes != ffi.nullptr && ref.bodyLen > 0) {
        bodyBytes = Uint8List.fromList(ref.bodyBytes.asTypedList(ref.bodyLen));
      }
      if (ref.headers != ffi.nullptr && ref.headerCount > 0) {
        final h = <String, String>{};
        for (var i = 0; i < ref.headerCount; i++) {
          final entry = ref.headers[i];
          if (entry.name == ffi.nullptr || entry.value == ffi.nullptr) continue;
          h[entry.name.toDartString().toLowerCase()] =
              entry.value.toDartString();
        }
        headers = h;
      }
      bindings.rac_http_response_free(respPtr);
    }
  } finally {
    calloc.free(respPtr);
    calloc.free(reqPtr);
    if (bodyLen > 0) {
      calloc.free(bodyPtr);
    }
    for (final p in headerNamePtrs) {
      calloc.free(p);
    }
    for (final p in headerValuePtrs) {
      calloc.free(p);
    }
    if (headerEntries.isNotEmpty) {
      calloc.free(headerArray);
    }
    calloc.free(methodPtr);
    calloc.free(urlPtr);
    bindings.rac_http_client_destroy(client);
  }

  return _HttpRequestResult(
    rc: rc,
    status: status,
    headers: headers,
    body: bodyBytes,
    elapsedMs: elapsedMs,
  );
}
