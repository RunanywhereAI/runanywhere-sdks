package com.runanywhere.sdk.services.auth

import com.runanywhere.sdk.data.models.AuthenticationRequest
import com.runanywhere.sdk.data.models.AuthenticationResponse
import com.runanywhere.sdk.data.models.HealthCheckResponse
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.APIClient
import com.runanywhere.sdk.security.KeychainManager
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Date

/**
 * Authentication Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles API authentication, token management, and health checks
 */
class AuthenticationService(
    private val apiClient: APIClient
) {
    private val logger = SDKLogger("AuthenticationService")
    private val mutex = Mutex()

    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var tokenExpiresAt: Date? = null

    /**
     * Authenticate with API key
     * Equivalent to iOS: func authenticate(apiKey: String) async throws -> AuthenticationResponse
     */
    suspend fun authenticate(apiKey: String): AuthenticationResponse = mutex.withLock {
        logger.debug("Starting authentication with API key")

        try {
            val request = AuthenticationRequest(
                apiKey = apiKey,
                deviceId = getDeviceId(),
                sdkVersion = getSdkVersion(),
                platform = "android"
            )

            val response = apiClient.post<AuthenticationRequest, AuthenticationResponse>(
                endpoint = "auth/authenticate",
                payload = request,
                requiresAuth = false
            )

            // Store tokens
            accessToken = response.accessToken
            refreshToken = response.refreshToken
            tokenExpiresAt = Date(System.currentTimeMillis() + (response.expiresIn * 1000L))

            // Save to keychain
            saveTokensToKeychain(response)

            logger.info("Authentication successful")
            return response

        } catch (e: Exception) {
            logger.error("Authentication failed", e)
            throw SDKError.AuthenticationFailed("Authentication failed: ${e.message}")
        }
    }

    /**
     * Get valid access token, refreshing if necessary
     * Equivalent to iOS: func getAccessToken() async throws -> String
     */
    suspend fun getAccessToken(): String = mutex.withLock {
        accessToken?.let { token ->
            if (isTokenValid()) {
                return token
            }
        }

        // Try to load from keychain
        loadStoredTokens()

        accessToken?.let { token ->
            if (isTokenValid()) {
                return token
            }
        }

        throw SDKError.InvalidAPIKey("No valid access token available")
    }

    /**
     * Perform health check
     * Equivalent to iOS: func healthCheck() async throws -> HealthCheckResponse
     */
    suspend fun healthCheck(): HealthCheckResponse {
        logger.debug("Performing health check")

        return try {
            apiClient.get<HealthCheckResponse>(
                endpoint = "health",
                requiresAuth = true
            )
        } catch (e: Exception) {
            logger.error("Health check failed", e)
            throw SDKError.NetworkError("Health check failed: ${e.message}")
        }
    }

    /**
     * Check if currently authenticated
     * Equivalent to iOS: func isAuthenticated() -> Bool
     */
    fun isAuthenticated(): Boolean {
        return accessToken != null && isTokenValid()
    }

    /**
     * Clear all authentication data
     * Equivalent to iOS: func clearAuthentication() async throws
     */
    suspend fun clearAuthentication() = mutex.withLock {
        logger.debug("Clearing authentication")

        accessToken = null
        refreshToken = null
        tokenExpiresAt = null

        // Clear from keychain
        KeychainManager.shared.deleteTokens()

        logger.info("Authentication cleared")
    }

    /**
     * Load stored tokens from keychain
     * Equivalent to iOS: func loadStoredTokens() async throws
     */
    suspend fun loadStoredTokens() = mutex.withLock {
        logger.debug("Loading stored tokens")

        try {
            val storedTokens = KeychainManager.shared.getTokens()
            storedTokens?.let { tokens ->
                accessToken = tokens.accessToken
                refreshToken = tokens.refreshToken
                tokenExpiresAt = tokens.expiresAt
                logger.debug("Loaded tokens from keychain")
            }
        } catch (e: Exception) {
            logger.error("Failed to load stored tokens", e)
            // Continue without stored tokens
        }
    }

    // Private helper methods

    private fun isTokenValid(): Boolean {
        val expiresAt = tokenExpiresAt ?: return false
        val now = Date()
        val fiveMinutesFromNow = Date(now.time + (5 * 60 * 1000)) // 5 minute buffer
        return expiresAt.after(fiveMinutesFromNow)
    }

    private fun saveTokensToKeychain(response: AuthenticationResponse) {
        try {
            KeychainManager.shared.saveTokens(
                accessToken = response.accessToken,
                refreshToken = response.refreshToken,
                expiresAt = Date(System.currentTimeMillis() + (response.expiresIn * 1000L))
            )
        } catch (e: Exception) {
            logger.error("Failed to save tokens to keychain", e)
            // Continue without keychain storage
        }
    }

    private fun getDeviceId(): String {
        // Implementation to get or generate device ID
        return android.os.Build.ID + "_" + android.os.Build.DEVICE
    }

    private fun getSdkVersion(): String {
        // Return SDK version
        return "1.0.0" // TODO: Get from build config
    }
}
