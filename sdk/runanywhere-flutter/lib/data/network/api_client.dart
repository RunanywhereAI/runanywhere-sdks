import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../foundation/configuration/sdk_constants.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../errors/repository_error.dart';
import 'api_endpoint.dart';
import 'network_service.dart';

/// Production API client for backend operations.
///
/// Matches iOS `APIClient` actor.
/// Implements NetworkService protocol for real network calls.
class APIClient implements NetworkService {
  // MARK: - Properties

  final Uri baseURL;
  final String apiKey;
  final http.Client _httpClient;
  final SDKLogger _logger;

  /// Optional auth service for getting access tokens.
  /// Set via `setAuthenticationService` after init.
  AuthTokenProvider? _authTokenProvider;

  // MARK: - Default Headers

  Map<String, String> get _defaultHeaders => {
        'Content-Type': 'application/json',
        'X-SDK-Client': 'RunAnywhereFlutterSDK',
        'X-SDK-Version': SDKConstants.version,
        'X-Platform': SDKConstants.platform,
        // Supabase-compatible headers (also works with standard backends)
        'apikey': apiKey,
        // Supabase: Request to return the created/updated row
        'Prefer': 'return=representation',
      };

  // MARK: - Initialization

  APIClient({
    required this.baseURL,
    required this.apiKey,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _logger = SDKLogger(category: 'APIClient');

  /// Set the authentication token provider (called after AuthenticationService is created).
  void setAuthTokenProvider(AuthTokenProvider provider) {
    _authTokenProvider = provider;
  }

  // MARK: - NetworkService Implementation

  @override
  Future<T> post<T>(
    APIEndpoint endpoint,
    Object payload, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final responseData = await postRaw(
      endpoint,
      _encodePayload(payload),
      requiresAuth: requiresAuth,
    );
    return _decodeResponse(responseData, fromJson);
  }

  @override
  Future<T> get<T>(
    APIEndpoint endpoint, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final responseData = await getRaw(
      endpoint,
      requiresAuth: requiresAuth,
    );
    return _decodeResponse(responseData, fromJson);
  }

  @override
  Future<Uint8List> postRaw(
    APIEndpoint endpoint,
    Uint8List payload, {
    required bool requiresAuth,
  }) async {
    return _postRawWithPath(endpoint.path, payload, requiresAuth: requiresAuth);
  }

  @override
  Future<Uint8List> getRaw(
    APIEndpoint endpoint, {
    required bool requiresAuth,
  }) async {
    return _getRawWithPath(endpoint.path, requiresAuth: requiresAuth);
  }

  @override
  Future<T> postWithPath<T>(
    String path,
    Object payload, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final responseData = await _postRawWithPath(
      path,
      _encodePayload(payload),
      requiresAuth: requiresAuth,
    );
    return _decodeResponse(responseData, fromJson);
  }

  @override
  Future<T> getWithPath<T>(
    String path, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final responseData =
        await _getRawWithPath(path, requiresAuth: requiresAuth);
    return _decodeResponse(responseData, fromJson);
  }

  // MARK: - Private Methods

  Future<Uint8List> _postRawWithPath(
    String path,
    Uint8List payload, {
    required bool requiresAuth,
  }) async {
    final token = await _getToken(requiresAuth);
    final url = baseURL.resolve(path);

    _logger.debug('POST $path');

    final headers = Map<String, String>.from(_defaultHeaders);
    headers['Authorization'] = 'Bearer $token';

    try {
      final response = await _httpClient
          .post(
            url,
            headers: headers,
            body: payload,
          )
          .timeout(const Duration(seconds: 30));

      _validateResponse(response);
      return response.bodyBytes;
    } catch (e) {
      if (e is RepositoryError) rethrow;
      _logger.error('POST $path failed: $e');
      throw RepositorySyncFailureError(e.toString());
    }
  }

  Future<Uint8List> _getRawWithPath(
    String path, {
    required bool requiresAuth,
  }) async {
    final token = await _getToken(requiresAuth);
    final url = baseURL.resolve(path);

    _logger.debug('GET $path');

    final headers = Map<String, String>.from(_defaultHeaders);
    headers['Authorization'] = 'Bearer $token';

    try {
      final response = await _httpClient
          .get(
            url,
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      _validateResponse(response);
      return response.bodyBytes;
    } catch (e) {
      if (e is RepositoryError) rethrow;
      _logger.error('GET $path failed: $e');
      throw RepositorySyncFailureError(e.toString());
    }
  }

  Future<String> _getToken(bool requiresAuth) async {
    if (requiresAuth && _authTokenProvider != null) {
      return await _authTokenProvider!.getAccessToken();
    }
    // No auth service or not required - use API key as bearer token (Supabase dev mode)
    return apiKey;
  }

  Uint8List _encodePayload(Object payload) {
    if (payload is Uint8List) return payload;
    if (payload is Map || payload is List) {
      return Uint8List.fromList(utf8.encode(json.encode(payload)));
    }
    // For objects with toJson method
    try {
      final jsonable = (payload as dynamic).toJson();
      return Uint8List.fromList(utf8.encode(json.encode(jsonable)));
    } catch (_) {
      throw ArgumentError('Payload must be Map, List, or have toJson() method');
    }
  }

  T _decodeResponse<T>(
      Uint8List data, T Function(Map<String, dynamic>) fromJson) {
    final jsonStr = utf8.decode(data);
    final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
    return fromJson(jsonMap);
  }

  void _validateResponse(http.Response response) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      return;
    }

    // Try to parse error response
    var errorMessage = 'HTTP ${response.statusCode}';

    try {
      final errorData = json.decode(response.body) as Map<String, dynamic>;

      // Try different error message formats
      if (errorData.containsKey('detail')) {
        final detail = errorData['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is List) {
          final errors = detail
              .whereType<Map<String, dynamic>>()
              .map((e) => e['msg'] as String?)
              .whereType<String>()
              .join(', ');
          if (errors.isNotEmpty) errorMessage = errors;
        }
      } else if (errorData.containsKey('message')) {
        errorMessage = errorData['message'] as String;
      } else if (errorData.containsKey('error')) {
        errorMessage = errorData['error'] as String;
      }
    } catch (_) {
      // Keep default error message if parsing fails
    }

    _logger.warning('Request failed: $errorMessage');
    throw RepositorySyncFailureError(errorMessage);
  }
}

/// Protocol for providing authentication tokens.
/// Implemented by AuthenticationService.
abstract class AuthTokenProvider {
  Future<String> getAccessToken();
}
