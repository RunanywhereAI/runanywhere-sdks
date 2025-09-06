package com.runanywhere.sdk.services

import com.runanywhere.sdk.data.models.AuthenticationResponse
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.HttpClient
import com.runanywhere.sdk.storage.SecureStorage
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.json.Json

/**
 * Common authentication service handling API key management, token refresh, etc.
 */
class AuthenticationService(
    private val secureStorage: SecureStorage,
    private val httpClient: HttpClient
) {
    private val logger = SDKLogger("AuthenticationService")
    private val json = Json { ignoreUnknownKeys = true }

    companion object {
        private const val KEY_API_KEY = "api_key"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_TOKEN_EXPIRY = "token_expiry"
        private const val KEY_USER_ID = "user_id"
    }

    private var cachedToken: String? = null
    private var tokenExpiry: Long = 0L

    /**
     * Initialize with API key
     */
    suspend fun initialize(apiKey: String) {
        logger.info("Initializing authentication service")
        secureStorage.setSecureString(KEY_API_KEY, apiKey)

        // Exchange API key for access token
        val token = exchangeApiKeyForToken(apiKey)
        if (token != null) {
            saveToken(token)
        }
    }

    /**
     * Get current access token, refreshing if needed
     */
    suspend fun getAccessToken(): String? {
        val currentTime = getCurrentTimeMillis()

        // Check cached token
        if (cachedToken != null && currentTime < tokenExpiry) {
            return cachedToken
        }

        // Try to load from storage
        val storedToken = secureStorage.getSecureString(KEY_ACCESS_TOKEN)
        val storedExpiry = secureStorage.getSecureString(KEY_TOKEN_EXPIRY)?.toLongOrNull() ?: 0L

        if (storedToken != null && currentTime < storedExpiry) {
            cachedToken = storedToken
            tokenExpiry = storedExpiry
            return storedToken
        }

        // Token expired, try to refresh
        val refreshToken = secureStorage.getSecureString(KEY_REFRESH_TOKEN)
        if (refreshToken != null) {
            val newToken = refreshAccessToken(refreshToken)
            if (newToken != null) {
                saveToken(newToken)
                return newToken.accessToken
            }
        }

        // Fall back to API key exchange
        val apiKey = secureStorage.getSecureString(KEY_API_KEY)
        if (apiKey != null) {
            val token = exchangeApiKeyForToken(apiKey)
            if (token != null) {
                saveToken(token)
                return token.accessToken
            }
        }

        logger.error("Failed to obtain access token")
        return null
    }

    /**
     * Get stored API key
     */
    suspend fun getApiKey(): String? {
        return secureStorage.getSecureString(KEY_API_KEY)
    }

    /**
     * Get current user ID
     */
    suspend fun getUserId(): String? {
        return secureStorage.getSecureString(KEY_USER_ID)
    }

    /**
     * Check if authenticated
     */
    suspend fun isAuthenticated(): Boolean {
        return getAccessToken() != null
    }

    /**
     * Sign out and clear credentials
     */
    suspend fun signOut() {
        logger.info("Signing out")
        cachedToken = null
        tokenExpiry = 0L
        secureStorage.clearSecure()
    }

    /**
     * Exchange API key for access token
     */
    private suspend fun exchangeApiKeyForToken(apiKey: String): AuthenticationResponse? {
        return try {
            val body = """{"api_key": "$apiKey"}""".encodeToByteArray()
            val response = httpClient.post(
                url = "https://api.runanywhere.ai/v1/auth/exchange",
                body = body,
                headers = mapOf("Content-Type" to "application/json")
            )

            if (response.isSuccessful) {
                json.decodeFromString<AuthenticationResponse>(response.bodyAsString())
            } else {
                logger.error("Token exchange failed: ${response.statusCode}")
                null
            }
        } catch (e: Exception) {
            logger.error("Error exchanging API key for token", e)
            null
        }
    }

    /**
     * Refresh access token using refresh token
     */
    private suspend fun refreshAccessToken(refreshToken: String): AuthenticationResponse? {
        return try {
            val body = """{"refresh_token": "$refreshToken"}""".encodeToByteArray()
            val response = httpClient.post(
                url = "https://api.runanywhere.ai/v1/auth/refresh",
                body = body,
                headers = mapOf("Content-Type" to "application/json")
            )

            if (response.isSuccessful) {
                json.decodeFromString<AuthenticationResponse>(response.bodyAsString())
            } else {
                logger.error("Token refresh failed: ${response.statusCode}")
                null
            }
        } catch (e: Exception) {
            logger.error("Error refreshing token", e)
            null
        }
    }

    /**
     * Save token to secure storage
     */
    private suspend fun saveToken(token: AuthenticationResponse) {
        val currentTime = getCurrentTimeMillis()
        cachedToken = token.accessToken
        tokenExpiry = currentTime + (token.expiresIn * 1000)

        secureStorage.setSecureString(KEY_ACCESS_TOKEN, token.accessToken)
        secureStorage.setSecureString(KEY_TOKEN_EXPIRY, tokenExpiry.toString())
        secureStorage.setSecureString(KEY_REFRESH_TOKEN, token.refreshToken)

        // Note: AuthenticationResponse doesn't have userId, so we skip it
    }
}
