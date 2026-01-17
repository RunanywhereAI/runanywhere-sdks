import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:runanywhere/data/network/network_configuration.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// HTTP Service - Core network implementation using dart:http
///
/// Centralized HTTP transport layer matching Swift/React Native HTTPService.
/// Uses the http package as the HTTP client.
///
/// Features:
/// - Environment-aware routing (Supabase for dev, Railway for prod)
/// - Automatic header management
/// - Proper timeout and error handling
/// - Device registration with Supabase UPSERT support
///
/// Usage:
/// ```dart
/// // Configure (called during SDK init)
/// HTTPService.shared.configure(HTTPServiceConfig(
///   baseURL: 'https://api.runanywhere.ai',
///   apiKey: 'your-api-key',
///   environment: SDKEnvironment.production,
/// ));
///
/// // Make requests
/// final response = await HTTPService.shared.post('/api/v1/devices/register', deviceData);
/// ```
class HTTPService {
  // ============================================================================
  // Singleton
  // ============================================================================

  static HTTPService? _instance;

  /// Get shared HTTPService instance
  static HTTPService get shared {
    _instance ??= HTTPService._();
    return _instance!;
  }

  // ============================================================================
  // Configuration
  // ============================================================================

  String _baseURL = '';
  String _apiKey = '';
  SDKEnvironment _environment = SDKEnvironment.production;
  String? _accessToken;
  Duration _timeout = const Duration(seconds: 30);

  // Development mode (Supabase)
  String _supabaseURL = '';
  String _supabaseKey = '';

  final http.Client _httpClient;
  final SDKLogger _logger;

  // ============================================================================
  // Initialization
  // ============================================================================

  HTTPService._()
      : _httpClient = http.Client(),
        _logger = SDKLogger('HTTPService');

  Map<String, String> get _defaultHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-SDK-Client': 'RunAnywhereFlutterSDK',
        'X-SDK-Version': SDKConstants.version,
        'X-Platform': SDKConstants.platform,
      };

  // ============================================================================
  // Configuration Methods
  // ============================================================================

  /// Configure HTTP service with base URL and API key
  void configure(HTTPServiceConfig config) {
    _baseURL = config.baseURL;
    _apiKey = config.apiKey;
    _environment = config.environment;
    _timeout = Duration(milliseconds: config.timeoutMs);

    _logger.info(
      'Configured for ${_getEnvironmentName()} environment: ${_getHostname(config.baseURL)}',
    );
  }

  /// Configure development mode with Supabase credentials
  ///
  /// When in development mode, SDK makes calls directly to Supabase
  /// instead of going through the Railway backend.
  void configureDev(DevModeConfig config) {
    _supabaseURL = config.supabaseURL;
    _supabaseKey = config.supabaseKey;

    _logger.info('Development mode configured with Supabase');
  }

  /// Set authorization token
  void setToken(String token) {
    _accessToken = token;
    _logger.debug('Access token set');
  }

  /// Clear authorization token
  void clearToken() {
    _accessToken = null;
    _logger.debug('Access token cleared');
  }

  /// Check if HTTP service is configured
  bool get isConfigured {
    if (_environment == SDKEnvironment.development) {
      return _supabaseURL.isNotEmpty;
    }
    return _baseURL.isNotEmpty && _apiKey.isNotEmpty;
  }

  /// Get current base URL
  String get currentBaseURL {
    if (_environment == SDKEnvironment.development && _supabaseURL.isNotEmpty) {
      return _supabaseURL;
    }
    return _baseURL;
  }

  /// Get current environment
  SDKEnvironment get environment => _environment;

  // ============================================================================
  // HTTP Methods
  // ============================================================================

  /// POST request with JSON body
  ///
  /// [path] - API endpoint path
  /// [data] - Request body (will be JSON serialized)
  /// Returns parsed response data
  Future<T> post<T>(
    String path,
    Object? data, {
    T Function(Map<String, dynamic>)? fromJson,
    bool requiresAuth = false,
  }) async {
    var url = _buildFullURL(path);

    // Handle device registration - add UPSERT for Supabase
    final isDeviceReg = _isDeviceRegistrationPath(path);
    final headers = _buildHeaders(isDeviceReg, requiresAuth);

    if (isDeviceReg && _environment == SDKEnvironment.development) {
      final separator = url.contains('?') ? '&' : '?';
      url = '$url${separator}on_conflict=device_id';
    }

    final response = await _executeRequest('POST', url, headers, data);

    // Handle 409 as success for device registration (device already exists)
    if (isDeviceReg && response.statusCode == 409) {
      _logger.info('Device already registered (409) - treating as success');
      return _parseResponse<T>(response, fromJson);
    }

    return _handleResponse<T>(response, path, fromJson);
  }

  /// POST request returning raw bytes
  Future<Uint8List> postRaw(
    String path,
    Uint8List payload, {
    bool requiresAuth = false,
  }) async {
    var url = _buildFullURL(path);

    final isDeviceReg = _isDeviceRegistrationPath(path);
    final headers = _buildHeaders(isDeviceReg, requiresAuth);

    if (isDeviceReg && _environment == SDKEnvironment.development) {
      final separator = url.contains('?') ? '&' : '?';
      url = '$url${separator}on_conflict=device_id';
    }

    final uri = Uri.parse(url);
    _logger.debug('POST $path');

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: payload,
          )
          .timeout(_timeout);

      if (isDeviceReg && response.statusCode == 409) {
        _logger.info('Device already registered (409) - treating as success');
        return response.bodyBytes;
      }

      _validateResponse(response, path);
      return response.bodyBytes;
    } catch (e) {
      if (e is SDKError) rethrow;
      _logger.error('POST $path failed: $e');
      throw SDKError.networkError(e.toString());
    }
  }

  /// GET request
  ///
  /// [path] - API endpoint path
  /// Returns parsed response data
  Future<T> get<T>(
    String path, {
    T Function(Map<String, dynamic>)? fromJson,
    bool requiresAuth = false,
  }) async {
    final url = _buildFullURL(path);
    final headers = _buildHeaders(false, requiresAuth);

    final response = await _executeRequest('GET', url, headers, null);
    return _handleResponse<T>(response, path, fromJson);
  }

  /// GET request returning raw bytes
  Future<Uint8List> getRaw(
    String path, {
    bool requiresAuth = false,
  }) async {
    final url = _buildFullURL(path);
    final headers = _buildHeaders(false, requiresAuth);

    final uri = Uri.parse(url);
    _logger.debug('GET $path');

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(_timeout);

      _validateResponse(response, path);
      return response.bodyBytes;
    } catch (e) {
      if (e is SDKError) rethrow;
      _logger.error('GET $path failed: $e');
      throw SDKError.networkError(e.toString());
    }
  }

  /// PUT request
  ///
  /// [path] - API endpoint path
  /// [data] - Request body
  /// Returns parsed response data
  Future<T> put<T>(
    String path,
    Object? data, {
    T Function(Map<String, dynamic>)? fromJson,
    bool requiresAuth = false,
  }) async {
    final url = _buildFullURL(path);
    final headers = _buildHeaders(false, requiresAuth);

    final response = await _executeRequest('PUT', url, headers, data);
    return _handleResponse<T>(response, path, fromJson);
  }

  /// DELETE request
  ///
  /// [path] - API endpoint path
  /// Returns parsed response data
  Future<T> delete<T>(
    String path, {
    T Function(Map<String, dynamic>)? fromJson,
    bool requiresAuth = false,
  }) async {
    final url = _buildFullURL(path);
    final headers = _buildHeaders(false, requiresAuth);

    final response = await _executeRequest('DELETE', url, headers, null);
    return _handleResponse<T>(response, path, fromJson);
  }

  // ============================================================================
  // Private Implementation
  // ============================================================================

  Future<http.Response> _executeRequest(
    String method,
    String url,
    Map<String, String> headers,
    Object? data,
  ) async {
    final uri = Uri.parse(url);
    _logger.debug('$method $url');

    try {
      late http.Response response;

      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
          break;
        case 'POST':
          final body = data != null ? json.encode(data) : null;
          // Debug: Log request body for telemetry debugging
          if (url.contains('telemetry')) {
            _logger.debug('POST body: $body');
          }
          response = await _httpClient
              .post(
                uri,
                headers: headers,
                body: body,
              )
              .timeout(_timeout);
          // Debug: Log response for telemetry debugging
          if (url.contains('telemetry')) {
            _logger.debug('Response status: ${response.statusCode}');
            _logger.debug('Response body: ${response.body}');
          }
          break;
        case 'PUT':
          response = await _httpClient
              .put(
                uri,
                headers: headers,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(_timeout);
          break;
        case 'DELETE':
          response = await _httpClient.delete(uri, headers: headers).timeout(_timeout);
          break;
        default:
          throw SDKError.networkError('Unsupported HTTP method: $method');
      }

      return response;
    } on TimeoutException {
      _logger.error('$method $url timed out');
      throw SDKError.timeout('Request timed out');
    } catch (e) {
      if (e is SDKError) rethrow;
      _logger.error('$method $url failed: $e');
      throw SDKError.networkError(e.toString());
    }
  }

  Map<String, String> _buildHeaders(bool isDeviceRegistration, bool requiresAuth) {
    final headers = Map<String, String>.from(_defaultHeaders);

    if (_environment == SDKEnvironment.development) {
      // Development mode - use Supabase headers
      // Supabase requires BOTH apikey AND Authorization: Bearer headers
      if (_supabaseKey.isNotEmpty) {
        headers['apikey'] = _supabaseKey;
        headers['Authorization'] = 'Bearer $_supabaseKey';
        headers['Prefer'] = isDeviceRegistration
            ? 'resolution=merge-duplicates'
            : 'return=representation';
      }
    } else {
      // Production/Staging - use Bearer token
      final token = _accessToken ?? _apiKey;
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      // Also add apikey for production (Railway backend)
      if (_apiKey.isNotEmpty) {
        headers['apikey'] = _apiKey;
      }
    }

    return headers;
  }

  String _buildFullURL(String path) {
    // Handle full URLs
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final base = currentBaseURL.endsWith('/')
        ? currentBaseURL.substring(0, currentBaseURL.length - 1)
        : currentBaseURL;
    final endpoint = path.startsWith('/') ? path : '/$path';
    return '$base$endpoint';
  }

  bool _isDeviceRegistrationPath(String path) {
    return path.contains('sdk_devices') ||
        path.contains('devices/register') ||
        path.contains('rest/v1/sdk_devices');
  }

  T _parseResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>)? fromJson,
  ) {
    final text = response.body;
    if (text.isEmpty) {
      return {} as T;
    }
    try {
      final decoded = json.decode(text);
      if (fromJson != null && decoded is Map<String, dynamic>) {
        return fromJson(decoded);
      }
      return decoded as T;
    } catch (_) {
      return text as T;
    }
  }

  T _handleResponse<T>(
    http.Response response,
    String path,
    T Function(Map<String, dynamic>)? fromJson,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseResponse<T>(response, fromJson);
    }

    // Parse error response
    var errorMessage = 'HTTP ${response.statusCode}';
    try {
      final errorData = json.decode(response.body) as Map<String, dynamic>;
      errorMessage = (errorData['message'] as String?) ??
          (errorData['error'] as String?) ??
          (errorData['hint'] as String?) ??
          errorMessage;
    } catch (_) {
      // Ignore JSON parse errors
    }

    _logger.error('HTTP ${response.statusCode}: $path');
    throw _createError(response.statusCode, errorMessage, path);
  }

  void _validateResponse(http.Response response, String path) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    var errorMessage = 'HTTP ${response.statusCode}';
    try {
      final errorData = json.decode(response.body) as Map<String, dynamic>;
      errorMessage = (errorData['message'] as String?) ??
          (errorData['error'] as String?) ??
          (errorData['hint'] as String?) ??
          errorMessage;
    } catch (_) {
      // Keep default error message if parsing fails
    }

    _logger.error('HTTP ${response.statusCode}: $path - $errorMessage');
    throw _createError(response.statusCode, errorMessage, path);
  }

  SDKError _createError(int statusCode, String message, String path) {
    switch (statusCode) {
      case 400:
        return SDKError.networkError('Bad request: $message');
      case 401:
        return SDKError.authenticationFailed(message);
      case 403:
        return SDKError.authenticationFailed('Forbidden: $message');
      case 404:
        return SDKError.networkError('Not found: $path');
      case 429:
        return SDKError.rateLimitExceeded('Rate limited: $message');
      case 500:
      case 502:
      case 503:
      case 504:
        return SDKError.serverError('Server error ($statusCode): $message');
      default:
        return SDKError.networkError('HTTP $statusCode: $message');
    }
  }

  String _getEnvironmentName() {
    switch (_environment) {
      case SDKEnvironment.development:
        return 'development';
      case SDKEnvironment.staging:
        return 'staging';
      case SDKEnvironment.production:
        return 'production';
    }
  }

  String _getHostname(String url) {
    // Simple hostname extraction
    final match = RegExp(r'^https?://([^/:]+)').firstMatch(url);
    return match != null ? match.group(1)! : url.substring(0, 30.clamp(0, url.length));
  }

  /// Reset for testing
  static void resetForTesting() {
    _instance = null;
  }
}
