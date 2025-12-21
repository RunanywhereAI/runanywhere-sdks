import 'dart:async';

import '../../../foundation/configuration/sdk_constants.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../foundation/security/keychain_manager.dart';
import '../../../infrastructure/device/services/device_identity.dart';
import '../../errors/repository_error.dart';
import '../api_client.dart';
import '../api_endpoint.dart';
import '../models/auth/auth.dart';

/// Service responsible for authentication and token management.
///
/// Matches iOS `AuthenticationService` actor from RunAnywhere SDK.
/// Implements [AuthTokenProvider] for use with [APIClient].
class AuthenticationService implements AuthTokenProvider {
  // MARK: - Properties

  final APIClient _apiClient;
  final SDKLogger _logger = SDKLogger(category: 'AuthenticationService');

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;
  String? _deviceId;
  String? _userId;
  String? _organizationId;

  // Keychain keys (matching iOS)
  static const _accessTokenKey = 'com.runanywhere.sdk.accessToken';
  static const _refreshTokenKey = 'com.runanywhere.sdk.refreshToken';
  static const _deviceIdKey = 'com.runanywhere.sdk.deviceId';
  static const _userIdKey = 'com.runanywhere.sdk.userId';
  static const _organizationIdKey = 'com.runanywhere.sdk.organizationId';

  // MARK: - Initialization

  AuthenticationService({required APIClient apiClient})
      : _apiClient = apiClient;

  /// Create and configure authentication services for production/staging.
  ///
  /// Returns a configured [AuthenticationService] that's already authenticated.
  /// Throws if authentication fails.
  static Future<AuthenticationService> createAndAuthenticate({
    required Uri baseURL,
    required String apiKey,
  }) async {
    final apiClient = APIClient(baseURL: baseURL, apiKey: apiKey);
    final authService = AuthenticationService(apiClient: apiClient);
    apiClient.setAuthTokenProvider(authService);

    // Authenticate with backend
    await authService.authenticate(apiKey: apiKey);

    return authService;
  }

  /// Get the associated API client.
  APIClient get apiClient => _apiClient;

  // MARK: - Public Methods

  /// Authenticate with the backend and obtain access token.
  Future<AuthenticationResponse> authenticate({required String apiKey}) async {
    final deviceId = await DeviceIdentity.persistentUUID;

    final request = AuthenticationRequest(
      apiKey: apiKey,
      deviceId: deviceId,
      platform: SDKConstants.platform,
      sdkVersion: SDKConstants.version,
    );

    _logger.debug('Authenticating with backend');

    // Use APIClient for the authentication request (doesn't require auth)
    final authResponse = await _apiClient.post<AuthenticationResponse>(
      APIEndpoint.authenticate,
      request,
      requiresAuth: false,
      fromJson: AuthenticationResponse.fromJson,
    );

    // Store tokens and additional info
    _accessToken = authResponse.accessToken;
    _refreshToken = authResponse.refreshToken;
    _tokenExpiresAt =
        DateTime.now().add(Duration(seconds: authResponse.expiresIn));
    _deviceId = authResponse.deviceId;
    _userId = authResponse.userId;
    _organizationId = authResponse.organizationId;

    // Store in keychain for persistence
    await _storeTokensInKeychain(authResponse);

    _logger.info('Authentication successful');
    return authResponse;
  }

  /// Get current access token, refreshing if needed.
  /// Implements [AuthTokenProvider.getAccessToken].
  @override
  Future<String> getAccessToken() async {
    // Check if token exists and is valid (with 1 minute buffer)
    if (_accessToken != null && _tokenExpiresAt != null) {
      final bufferTime = DateTime.now().add(const Duration(minutes: 1));
      if (_tokenExpiresAt!.isAfter(bufferTime)) {
        return _accessToken!;
      }
    }

    // Try to refresh token if we have a refresh token
    if (_refreshToken != null) {
      return await _refreshAccessToken();
    }

    // Otherwise, we can't re-authenticate without API key
    throw const RepositoryAuthenticationError(
        'No valid token and no way to re-authenticate');
  }

  /// Perform health check.
  Future<HealthCheckResponse> healthCheck() async {
    _logger.debug('Performing health check');

    // Health check requires authentication
    return await _apiClient.get<HealthCheckResponse>(
      APIEndpoint.healthCheck,
      requiresAuth: true,
      fromJson: HealthCheckResponse.fromJson,
    );
  }

  /// Check if authenticated.
  bool get isAuthenticated => _accessToken != null;

  /// Clear authentication state.
  Future<void> clearAuthentication() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
    _deviceId = null;
    _userId = null;
    _organizationId = null;

    // Clear from keychain
    await KeychainManager.shared.delete(_accessTokenKey);
    await KeychainManager.shared.delete(_refreshTokenKey);
    await KeychainManager.shared.delete(_deviceIdKey);
    await KeychainManager.shared.delete(_userIdKey);
    await KeychainManager.shared.delete(_organizationIdKey);

    _logger.info('Authentication cleared');
  }

  /// Load tokens from keychain if available.
  Future<void> loadStoredTokens() async {
    final storedAccessToken =
        await KeychainManager.shared.retrieve(_accessTokenKey);
    if (storedAccessToken != null) {
      _accessToken = storedAccessToken;
      _logger.debug('Loaded stored access token from keychain');
    }

    final storedRefreshToken =
        await KeychainManager.shared.retrieve(_refreshTokenKey);
    if (storedRefreshToken != null) {
      _refreshToken = storedRefreshToken;
      _logger.debug('Loaded stored refresh token from keychain');
    }

    final storedDeviceId = await KeychainManager.shared.retrieve(_deviceIdKey);
    if (storedDeviceId != null) {
      _deviceId = storedDeviceId;
      _logger.debug('Loaded stored device ID from keychain');
    }

    final storedUserId = await KeychainManager.shared.retrieve(_userIdKey);
    if (storedUserId != null) {
      _userId = storedUserId;
      _logger.debug('Loaded stored user ID from keychain');
    }

    final storedOrgId =
        await KeychainManager.shared.retrieve(_organizationIdKey);
    if (storedOrgId != null) {
      _organizationId = storedOrgId;
      _logger.debug('Loaded stored organization ID from keychain');
    }
  }

  /// Get current device ID.
  String? get deviceId => _deviceId;

  /// Get current user ID.
  String? get userId => _userId;

  /// Get current organization ID.
  String? get organizationId => _organizationId;

  // MARK: - Private Methods

  Future<String> _refreshAccessToken() async {
    if (_refreshToken == null) {
      throw const RepositoryAuthenticationError('No refresh token available');
    }

    if (_deviceId == null) {
      throw const RepositoryAuthenticationError(
          'No device ID available for refresh');
    }

    _logger.debug('Refreshing access token');

    final request = RefreshTokenRequest(
      deviceId: _deviceId!,
      refreshToken: _refreshToken!,
    );

    // Call refresh endpoint
    final refreshResponse = await _apiClient.post<RefreshTokenResponse>(
      APIEndpoint.refreshToken,
      request,
      requiresAuth: false,
      fromJson: RefreshTokenResponse.fromJson,
    );

    // Update stored tokens and info
    _accessToken = refreshResponse.accessToken;
    _refreshToken = refreshResponse.refreshToken;
    _tokenExpiresAt =
        DateTime.now().add(Duration(seconds: refreshResponse.expiresIn));
    _deviceId = refreshResponse.deviceId;
    _userId = refreshResponse.userId;
    _organizationId = refreshResponse.organizationId;

    // Store updated tokens in keychain
    await _storeTokensInKeychain(refreshResponse);

    _logger.info('Token refresh successful');
    return refreshResponse.accessToken;
  }

  Future<void> _storeTokensInKeychain(AuthenticationResponse response) async {
    await KeychainManager.shared.store(_accessTokenKey, response.accessToken);
    await KeychainManager.shared.store(_refreshTokenKey, response.refreshToken);
    await KeychainManager.shared.store(_deviceIdKey, response.deviceId);
    if (response.userId != null) {
      await KeychainManager.shared.store(_userIdKey, response.userId!);
    }
    await KeychainManager.shared
        .store(_organizationIdKey, response.organizationId);
  }
}
