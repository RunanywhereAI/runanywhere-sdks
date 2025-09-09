package com.runanywhere.sdk.services

import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.HttpClient
import com.runanywhere.sdk.storage.SecureStorage
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import com.runanywhere.sdk.utils.PersistentDeviceIdentity
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.serialization.json.Json
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Service responsible for authentication and token management
 * Full parity with iOS AuthenticationService implementation
 */
class AuthenticationService(
    private val secureStorage: SecureStorage,
    private val httpClient: HttpClient
) {
    private val logger = SDKLogger("AuthenticationService")
    private val json = Json { ignoreUnknownKeys = true }

    // Thread safety mutex (replaces actor pattern from iOS)
    private val mutex = Mutex()

    // Storage keys (matching iOS KeychainManager pattern)
    companion object {
        // Authentication tokens
        private const val KEY_ACCESS_TOKEN = "com.runanywhere.sdk.accessToken"
        private const val KEY_REFRESH_TOKEN = "com.runanywhere.sdk.refreshToken"
        private const val KEY_TOKEN_EXPIRES_AT = "com.runanywhere.sdk.tokenExpiresAt"

        // API configuration
        private const val KEY_API_KEY = "com.runanywhere.sdk.apiKey"
        private const val KEY_BASE_URL = "com.runanywhere.sdk.baseURL"
        private const val KEY_ENVIRONMENT = "com.runanywhere.sdk.environment"

        // Device identity (matching iOS KeychainManager)
        private const val KEY_DEVICE_UUID = "com.runanywhere.sdk.device.uuid"
        private const val KEY_DEVICE_FINGERPRINT = "com.runanywhere.sdk.device.fingerprint"

        // Token buffer for refresh (1 minute like iOS)
        private const val TOKEN_REFRESH_BUFFER_MILLIS = 60_000L
    }

    // In-memory cache
    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var tokenExpiresAt: Long? = null

    /**
     * Authenticate with the backend and obtain access token
     * Matches iOS AuthenticationService.authenticate(apiKey:) method
     */
    suspend fun authenticate(apiKey: String): AuthenticationResponse = mutex.withLock {
        val deviceId = PersistentDeviceIdentity.getPersistentDeviceUUID()

        val request = AuthenticationRequest(
            apiKey = apiKey,
            deviceId = deviceId,
            sdkVersion = SDKConstants.version,
            platform = SDKConstants.platform
        )

        logger.debug("Authenticating with backend")

        try {
            val response = performAuthenticationRequest(request)

            // Store tokens in memory and secure storage
            this.accessToken = response.accessToken
            this.refreshToken = response.refreshToken
            this.tokenExpiresAt = getCurrentTimeMillis() + (response.expiresIn * 1000)

            // Store in secure storage for persistence
            storeTokensInSecureStorage(response)

            logger.info("Authentication successful")
            return response

        } catch (e: Exception) {
            logger.error("Authentication failed", e)
            throw SDKError.AuthenticationError("Authentication failed: ${e.message}")
        }
    }

    /**
     * Get current access token, refreshing if needed
     * Matches iOS AuthenticationService.getAccessToken() method
     */
    suspend fun getAccessToken(): String = mutex.withLock {
        // Check if token exists and is valid (with buffer like iOS)
        val currentTime = getCurrentTimeMillis()
        if (accessToken != null && tokenExpiresAt != null &&
            tokenExpiresAt!! > currentTime + TOKEN_REFRESH_BUFFER_MILLIS) {
            return accessToken!!
        }

        // Try to refresh token if we have a refresh token
        if (refreshToken != null) {
            try {
                return refreshAccessToken()
            } catch (e: Exception) {
                logger.error("Token refresh failed", e)
                // Continue to re-authentication error
            }
        }

        // Otherwise, we can't re-authenticate without API key
        throw SDKError.AuthenticationError("No valid token and no way to re-authenticate")
    }

    /**
     * Perform health check
     * Matches iOS AuthenticationService.healthCheck() method
     */
    suspend fun healthCheck(): HealthCheckResponse = mutex.withLock {
        logger.debug("Performing health check")

        try {
            // Health check requires authentication
            val token = getAccessToken()
            return performHealthCheckRequest(token)

        } catch (e: Exception) {
            logger.error("Health check failed", e)
            throw SDKError.NetworkError("Health check failed: ${e.message}")
        }
    }

    /**
     * Check if authenticated
     * Matches iOS AuthenticationService.isAuthenticated() method
     */
    fun isAuthenticated(): Boolean {
        return accessToken != null
    }

    /**
     * Clear authentication state
     * Matches iOS AuthenticationService.clearAuthentication() method
     */
    suspend fun clearAuthentication() = mutex.withLock {
        accessToken = null
        refreshToken = null
        tokenExpiresAt = null

        // Clear from secure storage
        try {
            secureStorage.removeSecure(KEY_ACCESS_TOKEN)
            secureStorage.removeSecure(KEY_REFRESH_TOKEN)
            secureStorage.removeSecure(KEY_TOKEN_EXPIRES_AT)

            logger.info("Authentication cleared")
        } catch (e: Exception) {
            logger.error("Failed to clear authentication from storage", e)
            throw SDKError.FileSystemError("Failed to clear authentication: ${e.message}")
        }
    }

    /**
     * Load tokens from secure storage if available
     * Matches iOS AuthenticationService.loadStoredTokens() method
     */
    suspend fun loadStoredTokens() = mutex.withLock {
        try {
            val storedAccessToken = secureStorage.getSecureString(KEY_ACCESS_TOKEN)
            if (storedAccessToken != null) {
                this.accessToken = storedAccessToken
                logger.debug("Loaded stored access token from secure storage")
            }

            val storedRefreshToken = secureStorage.getSecureString(KEY_REFRESH_TOKEN)
            if (storedRefreshToken != null) {
                this.refreshToken = storedRefreshToken
                logger.debug("Loaded stored refresh token from secure storage")
            }

            val storedExpiresAt = secureStorage.getSecureString(KEY_TOKEN_EXPIRES_AT)?.toLongOrNull()
            if (storedExpiresAt != null) {
                this.tokenExpiresAt = storedExpiresAt
                logger.debug("Loaded stored token expiry from secure storage")
            }

        } catch (e: Exception) {
            logger.error("Failed to load stored tokens", e)
            // Don't throw - this is optional recovery
        }
    }

    // MARK: - Private Methods

    /**
     * Perform authentication request
     */
    private suspend fun performAuthenticationRequest(request: AuthenticationRequest): AuthenticationResponse {
        val requestBody = json.encodeToString(AuthenticationRequest.serializer(), request)

        val response = httpClient.post(
            url = "https://api.runanywhere.ai/v1/auth/token", // Matches iOS endpoint
            body = requestBody.encodeToByteArray(),
            headers = mapOf(
                "Content-Type" to "application/json",
                "X-SDK-Client" to "RunAnywhereKotlinSDK",
                "X-SDK-Version" to SDKConstants.version,
                "X-Platform" to SDKConstants.platform
            )
        )

        if (!response.isSuccessful) {
            val errorMessage = "Authentication failed with status: ${response.statusCode}"
            logger.error(errorMessage)
            throw SDKError.AuthenticationError(errorMessage)
        }

        return json.decodeFromString<AuthenticationResponse>(response.bodyAsString())
    }

    /**
     * Refresh access token using refresh token
     */
    private suspend fun refreshAccessToken(): String {
        val currentRefreshToken = refreshToken
            ?: throw SDKError.InvalidAPIKey("No refresh token available")

        logger.info("Refresh token available but refresh endpoint not implemented")
        throw SDKError.AuthenticationError("Token refresh not implemented")

        // TODO: Implement when refresh endpoint is available
        /*
        val refreshRequest = mapOf("refresh_token" to currentRefreshToken)
        val requestBody = json.encodeToString(refreshRequest)

        val response = httpClient.post(
            url = "https://api.runanywhere.ai/v1/auth/refresh",
            body = requestBody.encodeToByteArray(),
            headers = mapOf(
                "Content-Type" to "application/json",
                "X-SDK-Client" to "RunAnywhereKotlinSDK",
                "X-SDK-Version" to SDKConstants.version,
                "X-Platform" to SDKConstants.platform
            )
        )

        if (!response.isSuccessful) {
            throw SDKError.AuthenticationError("Token refresh failed with status: ${response.statusCode}")
        }

        val authResponse = json.decodeFromString<AuthenticationResponse>(response.bodyAsString())

        // Update tokens
        this.accessToken = authResponse.accessToken
        this.refreshToken = authResponse.refreshToken
        this.tokenExpiresAt = getCurrentTimeMillis() + (authResponse.expiresIn * 1000)

        // Store in secure storage
        storeTokensInSecureStorage(authResponse)

        return authResponse.accessToken
        */
    }

    /**
     * Perform health check request
     */
    private suspend fun performHealthCheckRequest(accessToken: String): HealthCheckResponse {
        val response = httpClient.get(
            url = "https://api.runanywhere.ai/v1/health",
            headers = mapOf(
                "Authorization" to "Bearer $accessToken",
                "Content-Type" to "application/json",
                "X-SDK-Client" to "RunAnywhereKotlinSDK",
                "X-SDK-Version" to SDKConstants.version,
                "X-Platform" to SDKConstants.platform
            )
        )

        if (!response.isSuccessful) {
            throw SDKError.NetworkError("Health check failed with status: ${response.statusCode}")
        }

        return json.decodeFromString<HealthCheckResponse>(response.bodyAsString())
    }

    /**
     * Store tokens in secure storage for persistence
     * Matches iOS storeTokensInKeychain method
     */
    private suspend fun storeTokensInSecureStorage(response: AuthenticationResponse) {
        try {
            secureStorage.setSecureString(KEY_ACCESS_TOKEN, response.accessToken)
            secureStorage.setSecureString(KEY_REFRESH_TOKEN, response.refreshToken)
            tokenExpiresAt?.let { expiresAt ->
                secureStorage.setSecureString(KEY_TOKEN_EXPIRES_AT, expiresAt.toString())
            }
        } catch (e: Exception) {
            logger.error("Failed to store tokens in secure storage", e)
            throw SDKError.FileSystemError("Failed to store tokens: ${e.message}")
        }
    }
}
