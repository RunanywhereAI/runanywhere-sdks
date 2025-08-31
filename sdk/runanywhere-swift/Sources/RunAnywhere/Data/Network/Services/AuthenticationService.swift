import Foundation

/// Service responsible for authentication and token management
public actor AuthenticationService {

    // MARK: - Properties

    private let apiClient: APIClient
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private let logger = SDKLogger(category: "AuthenticationService")

    // MARK: - Initialization

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Authenticate with the backend and obtain access token
    public func authenticate(apiKey: String) async throws -> AuthenticationResponse {
        let deviceId = PersistentDeviceIdentity.getPersistentDeviceUUID()

        let request = AuthenticationRequest(
            apiKey: apiKey,
            deviceId: deviceId,
            sdkVersion: SDKConstants.version,
            platform: SDKConstants.platform
        )

        logger.debug("Authenticating with backend")

        // Use APIClient for the authentication request (doesn't require auth)
        let authResponse: AuthenticationResponse = try await apiClient.post(
            .authenticate,
            request,
            requiresAuth: false
        )

        // Store tokens
        self.accessToken = authResponse.accessToken
        self.refreshToken = authResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))

        // Store in keychain for persistence
        try await storeTokensInKeychain(authResponse)

        logger.info("Authentication successful")
        return authResponse
    }

    /// Get current access token, refreshing if needed
    public func getAccessToken() async throws -> String {
        // Check if token exists and is valid
        if let token = accessToken,
           let expiresAt = tokenExpiresAt,
           expiresAt > Date().addingTimeInterval(60) { // 1 minute buffer
            return token
        }

        // Try to refresh token if we have a refresh token
        if refreshToken != nil {
            return try await refreshAccessToken()
        }

        // Otherwise, we can't re-authenticate without API key
        throw SDKError.authenticationFailed("No valid token and no way to re-authenticate")
    }

    /// Perform health check
    public func healthCheck() async throws -> HealthCheckResponse {
        logger.debug("Performing health check")

        // Health check requires authentication
        return try await apiClient.get(
            .healthCheck,
            requiresAuth: true
        )
    }

    /// Check if authenticated
    public func isAuthenticated() -> Bool {
        return accessToken != nil
    }

    /// Clear authentication state
    public func clearAuthentication() async throws {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil

        // Clear from keychain
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")

        logger.info("Authentication cleared")
    }

    // MARK: - Private Methods

    private func refreshAccessToken() async throws -> String {
        guard refreshToken != nil else {
            throw SDKError.invalidAPIKey("No refresh token available")
        }

        // This would call a refresh endpoint - for now, we can't refresh without the original API key
        logger.info("Refresh token available but refresh endpoint not implemented")
        throw SDKError.authenticationFailed("Token refresh not implemented")
    }

    private func storeTokensInKeychain(_ response: AuthenticationResponse) async throws {
        try KeychainManager.shared.store(response.accessToken, for: "com.runanywhere.sdk.accessToken")
        if let refreshToken = response.refreshToken {
            try KeychainManager.shared.store(refreshToken, for: "com.runanywhere.sdk.refreshToken")
        }
    }

    /// Load tokens from keychain if available
    public func loadStoredTokens() async throws {
        if let storedAccessToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.accessToken") {
            self.accessToken = storedAccessToken
            logger.debug("Loaded stored access token from keychain")
        }

        if let storedRefreshToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.refreshToken") {
            self.refreshToken = storedRefreshToken
            logger.debug("Loaded stored refresh token from keychain")
        }
    }
}
