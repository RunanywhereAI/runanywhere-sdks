import Foundation

/// Service responsible for authentication and token management
public actor AuthenticationService {

    // MARK: - Properties

    private let apiClient: APIClient
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var deviceId: String?
    private var userId: String?  // Optional since API can return null for now if org_level
    private var organizationId: String?
    private let logger = SDKLogger(category: "AuthenticationService")

    // MARK: - Initialization

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Create and configure authentication services for production/staging
    /// - Parameters:
    ///   - baseURL: The API base URL
    ///   - apiKey: The API key for authentication
    /// - Returns: Tuple of configured (APIClient, AuthenticationService)
    /// - Throws: If authentication fails
    public static func createAndAuthenticate(
        baseURL: URL,
        apiKey: String
    ) async throws -> (apiClient: APIClient, authService: AuthenticationService) {
        let apiClient = APIClient(baseURL: baseURL, apiKey: apiKey)
        let authService = AuthenticationService(apiClient: apiClient)
        await apiClient.setAuthenticationService(authService)

        // Authenticate with backend
        _ = try await authService.authenticate(apiKey: apiKey)

        return (apiClient, authService)
    }

    // MARK: - Public Methods

    /// Authenticate with the backend and obtain access token
    public func authenticate(apiKey: String) async throws -> AuthenticationResponse {
        let deviceId = DeviceIdentity.persistentUUID

        let request = AuthenticationRequest(
            apiKey: apiKey,
            deviceId: deviceId,
            platform: SDKConstants.platform,
            sdkVersion: SDKConstants.version
        )

        logger.debug("Authenticating with backend")

        // Use APIClient for the authentication request (doesn't require auth)
        let authResponse: AuthenticationResponse = try await apiClient.post(
            .authenticate,
            request,
            requiresAuth: false
        )

        // Store tokens and additional info
        self.accessToken = authResponse.accessToken
        self.refreshToken = authResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
        self.deviceId = authResponse.deviceId
        self.userId = authResponse.userId
        self.organizationId = authResponse.organizationId

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
        throw RunAnywhereError.authenticationFailed("No valid token and no way to re-authenticate")
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
        deviceId = nil
        userId = nil
        organizationId = nil

        // Clear from keychain
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.deviceId")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.userId")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.organizationId")

        logger.info("Authentication cleared")
    }

    // MARK: - Private Methods

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = refreshToken else {
            throw RunAnywhereError.invalidAPIKey("No refresh token available")
        }

        guard let deviceId = deviceId else {
            throw RunAnywhereError.authenticationFailed("No device ID available for refresh")
        }

        logger.debug("Refreshing access token")

        let request = RefreshTokenRequest(
            deviceId: deviceId,
            refreshToken: refreshToken
        )

        // Call refresh endpoint
        let refreshResponse: RefreshTokenResponse = try await apiClient.post(
            .refreshToken,
            request,
            requiresAuth: false
        )

        // Update stored tokens and info
        self.accessToken = refreshResponse.accessToken
        self.refreshToken = refreshResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(refreshResponse.expiresIn))
        self.deviceId = refreshResponse.deviceId
        self.userId = refreshResponse.userId
        self.organizationId = refreshResponse.organizationId

        // Store updated tokens in keychain
        try await storeTokensInKeychain(refreshResponse)

        logger.info("Token refresh successful")
        return refreshResponse.accessToken
    }

    private func storeTokensInKeychain(_ response: AuthenticationResponse) async throws {
        try KeychainManager.shared.store(response.accessToken, for: "com.runanywhere.sdk.accessToken")
        try KeychainManager.shared.store(response.refreshToken, for: "com.runanywhere.sdk.refreshToken")
        try KeychainManager.shared.store(response.deviceId, for: "com.runanywhere.sdk.deviceId")
        if let userId = response.userId {
            try KeychainManager.shared.store(userId, for: "com.runanywhere.sdk.userId")
        }
        try KeychainManager.shared.store(response.organizationId, for: "com.runanywhere.sdk.organizationId")
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

        if let storedDeviceId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.deviceId") {
            self.deviceId = storedDeviceId
            logger.debug("Loaded stored device ID from keychain")
        }

        if let storedUserId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.userId") {
            self.userId = storedUserId
            logger.debug("Loaded stored user ID from keychain")
        }

        if let storedOrgId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.organizationId") {
            self.organizationId = storedOrgId
            logger.debug("Loaded stored organization ID from keychain")
        }
    }

    /// Get current device ID
    public func getDeviceId() -> String? {
        return deviceId
    }

    /// Get current user ID
    public func getUserId() -> String? {
        return userId
    }

    /// Get current organization ID
    public func getOrganizationId() -> String? {
        return organizationId
    }

    /// Register device with backend
    /// Uses unified DeviceRegistrationRequest for all environments
    public func registerDevice() async throws -> DeviceRegistrationResponse {
        logger.debug("Registering device with backend")

        // Create request from current device info
        let request = DeviceRegistrationRequest.fromCurrentDevice()

        // Make API call with authentication
        let response: DeviceRegistrationResponse = try await apiClient.post(
            .deviceRegistration,
            request,
            requiresAuth: true
        )

        logger.info("Device registration successful: \(response.deviceId)")
        return response
    }
}
