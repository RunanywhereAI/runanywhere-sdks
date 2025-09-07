package com.runanywhere.sdk.network

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Authentication service for managing API authentication
 */
interface AuthenticationService {
    suspend fun authenticate(apiKey: String): AuthenticationResponse
    suspend fun refreshToken(): String
    suspend fun getAccessToken(): String
    fun isAuthenticated(): Boolean
    fun clearAuthentication()
    suspend fun healthCheck(): HealthCheckResponse
}

/**
 * Authentication request model
 */
@Serializable
data class AuthenticationRequest(
    val apiKey: String,
    val deviceId: String,
    val sdkVersion: String,
    val platform: String,
    val deviceInfo: Map<String, String>? = null
)

/**
 * Authentication response model
 */
@Serializable
data class AuthenticationResponse(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresIn: Long = 3600, // seconds
    val userId: String? = null,
    val limits: Map<String, Int>? = null
)

/**
 * Health check response
 */
@Serializable
data class HealthCheckResponse(
    val status: String,
    val version: String,
    val timestamp: Long
)

/**
 * Default implementation of AuthenticationService
 */
class DefaultAuthenticationService(
    private val apiClient: APIClient,
    private val secureStorage: com.runanywhere.sdk.storage.SecureStorage
) : AuthenticationService {

    private val logger = SDKLogger("AuthenticationService")
    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var tokenExpiresAt: Long? = null

    companion object {
        private const val ACCESS_TOKEN_KEY = "com.runanywhere.sdk.accessToken"
        private const val REFRESH_TOKEN_KEY = "com.runanywhere.sdk.refreshToken"
        private const val TOKEN_EXPIRY_KEY = "com.runanywhere.sdk.tokenExpiry"
        private const val TOKEN_BUFFER_SECONDS = 60 // 1 minute buffer before expiry
    }

    override suspend fun authenticate(apiKey: String): AuthenticationResponse {
        logger.debug("Authenticating with backend")

        // Validate API key format
        if (!isValidApiKey(apiKey)) {
            throw SDKError.InvalidAPIKey("Invalid API key format")
        }

        // Get or create device ID
        val deviceId = PlatformUtils.getDeviceId()

        // Create authentication request
        val request = AuthenticationRequest(
            apiKey = apiKey,
            deviceId = deviceId,
            sdkVersion = "0.1.0",
            platform = PlatformUtils.getPlatformName(),
            deviceInfo = PlatformUtils.getDeviceInfo()
        )

        try {
            // Call authentication endpoint
            val response = apiClient.postJson<AuthenticationRequest, AuthenticationResponse>(
                endpoint = "v1/auth/authenticate",
                payload = request,
                requiresAuth = false
            )

            // Store tokens
            storeTokens(response)

            logger.info("Authentication successful")
            return response

        } catch (e: Exception) {
            logger.error("Authentication failed", e)
            throw SDKError.NetworkError("Authentication failed: ${e.message}")
        }
    }

    override suspend fun refreshToken(): String {
        val currentRefreshToken = refreshToken
            ?: throw SDKError.InvalidAPIKey("No refresh token available")

        logger.debug("Refreshing access token")

        try {
            val response = apiClient.postJson<Map<String, String>, AuthenticationResponse>(
                endpoint = "v1/auth/refresh",
                payload = mapOf("refreshToken" to currentRefreshToken),
                requiresAuth = false
            )

            // Store new tokens
            storeTokens(response)

            logger.info("Token refresh successful")
            return response.accessToken

        } catch (e: Exception) {
            logger.error("Token refresh failed", e)
            throw SDKError.NetworkError("Token refresh failed: ${e.message}")
        }
    }

    override suspend fun getAccessToken(): String {
        // Check if token exists and is valid
        val token = accessToken
        val expiresAt = tokenExpiresAt

        if (token != null && expiresAt != null) {
            val now = getCurrentTimeMillis() / 1000 // convert to seconds
            if (expiresAt > now + TOKEN_BUFFER_SECONDS) {
                return token
            }
        }

        // Try to refresh token if we have a refresh token
        if (refreshToken != null) {
            return refreshToken()
        }

        throw SDKError.InvalidAPIKey("No valid token and no way to re-authenticate")
    }

    override fun isAuthenticated(): Boolean {
        return accessToken != null
    }

    override fun clearAuthentication() {
        accessToken = null
        refreshToken = null
        tokenExpiresAt = null

        // Clear from secure storage
        secureStorage.removeSecure(ACCESS_TOKEN_KEY)
        secureStorage.removeSecure(REFRESH_TOKEN_KEY)
        secureStorage.removeSecure(TOKEN_EXPIRY_KEY)

        logger.info("Authentication cleared")
    }

    override suspend fun healthCheck(): HealthCheckResponse {
        logger.debug("Performing health check")

        return apiClient.getJson(
            endpoint = "v1/health",
            requiresAuth = true
        )
    }

    // Private helper methods

    private fun isValidApiKey(apiKey: String): Boolean {
        // Basic validation - adjust based on your API key format
        return apiKey.isNotEmpty() &&
               apiKey.length >= 32 &&
               apiKey.matches(Regex("^[a-zA-Z0-9_-]+$"))
    }

    private fun storeTokens(response: AuthenticationResponse) {
        val now = getCurrentTimeMillis() / 1000 // convert to seconds

        accessToken = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiresAt = now + response.expiresIn

        // Store in secure storage for persistence
        secureStorage.setSecureString(ACCESS_TOKEN_KEY, response.accessToken)
        response.refreshToken?.let {
            secureStorage.setSecureString(REFRESH_TOKEN_KEY, it)
        }
        secureStorage.setSecureString(TOKEN_EXPIRY_KEY, tokenExpiresAt.toString())
    }

    suspend fun loadStoredTokens() {
        try {
            accessToken = secureStorage.getSecureString(ACCESS_TOKEN_KEY)
            refreshToken = secureStorage.getSecureString(REFRESH_TOKEN_KEY)
            secureStorage.getSecureString(TOKEN_EXPIRY_KEY)?.toLongOrNull()?.let {
                tokenExpiresAt = it
            }

            if (accessToken != null) {
                logger.debug("Loaded stored tokens")
            }
        } catch (e: Exception) {
            logger.error("Failed to load stored tokens", e)
        }
    }
}
