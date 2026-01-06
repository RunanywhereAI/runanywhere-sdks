/**
 * CppBridge+Auth.kt
 * RunAnywhere SDK
 *
 * Authentication bridge extension for production/staging mode.
 * Handles full auth flow: JSON building, HTTP, parsing, state storage.
 *
 * Mirrors Swift SDK's CppBridge+Auth.swift implementation.
 */
package com.runanywhere.sdk.foundation.bridge.extensions

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicReference

/**
 * Authentication response from the backend
 */
@Serializable
data class AuthenticationResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("expires_in") val expiresIn: Int,
    @SerialName("organization_id") val organizationId: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("token_type") val tokenType: String,
    @SerialName("user_id") val userId: String? = null
)

/**
 * Authentication request body
 */
@Serializable
data class AuthenticationRequest(
    @SerialName("api_key") val apiKey: String,
    @SerialName("device_id") val deviceId: String,
    val platform: String,
    @SerialName("sdk_version") val sdkVersion: String
)

/**
 * Refresh token request body
 */
@Serializable
data class RefreshTokenRequest(
    @SerialName("device_id") val deviceId: String,
    @SerialName("refresh_token") val refreshToken: String
)

/**
 * Authentication bridge for production/staging mode.
 * Handles JWT token acquisition and management.
 */
object CppBridgeAuth {
    private const val TAG = "CppBridge/Auth"
    private const val ENDPOINT_AUTHENTICATE = "/api/v1/auth/sdk/authenticate"
    private const val ENDPOINT_REFRESH = "/api/v1/auth/sdk/refresh"
    
    // Authentication state
    private val _accessToken = AtomicReference<String?>(null)
    private val _refreshToken = AtomicReference<String?>(null)
    private val _deviceId = AtomicReference<String?>(null)
    private val _organizationId = AtomicReference<String?>(null)
    private val _userId = AtomicReference<String?>(null)
    private val _expiresAt = AtomicReference<Long?>(null)
    private val _baseUrl = AtomicReference<String?>(null)
    private val _apiKey = AtomicReference<String?>(null)
    
    private val json = Json { 
        ignoreUnknownKeys = true 
        isLenient = true
    }
    
    /**
     * Current access token (JWT) for Bearer authentication.
     * Use getValidToken() instead for automatic refresh handling.
     */
    val accessToken: String?
        get() = _accessToken.get()
    
    /**
     * Check if token needs refresh (expires within 5 minutes)
     */
    val tokenNeedsRefresh: Boolean
        get() {
            val expiresAt = _expiresAt.get() ?: return true
            val nowMs = System.currentTimeMillis()
            val fiveMinutesMs = 5 * 60 * 1000
            return nowMs >= (expiresAt - fiveMinutesMs)
        }
    
    /**
     * Check if currently authenticated
     */
    val isAuthenticated: Boolean
        get() = _accessToken.get() != null && !tokenNeedsRefresh
    
    /**
     * Get a valid access token, automatically refreshing if needed.
     * This is the preferred way to get the token for requests.
     * 
     * @return Valid access token, or null if not authenticated and can't refresh
     */
    fun getValidToken(): String? {
        val currentToken = _accessToken.get()
        
        // If we have a valid token, return it
        if (currentToken != null && !tokenNeedsRefresh) {
            return currentToken
        }
        
        // Try to refresh if we have refresh token and base URL
        val refreshToken = _refreshToken.get()
        val baseUrl = _baseUrl.get()
        
        if (refreshToken != null && baseUrl != null) {
            try {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "🔄 Token expired or expiring soon, refreshing..."
                )
                return refreshAccessToken(baseUrl)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "❌ Token refresh failed: ${e.message}"
                )
                
                // Try re-authenticating if we have API key
                val apiKey = _apiKey.get()
                val deviceId = _deviceId.get()
                if (apiKey != null && deviceId != null) {
                    try {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.INFO,
                            TAG,
                            "🔐 Refresh failed, re-authenticating..."
                        )
                        authenticate(apiKey, baseUrl, deviceId)
                        return _accessToken.get()
                    } catch (authE: Exception) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.ERROR,
                            TAG,
                            "❌ Re-authentication failed: ${authE.message}"
                        )
                    }
                }
            }
        }
        
        // Return current token even if expired (caller will get 401)
        return currentToken
    }
    
    /**
     * Authenticate with the backend using API key.
     * Gets a JWT access token for subsequent requests.
     *
     * @param apiKey The API key for authentication
     * @param baseUrl The backend base URL
     * @param deviceId The device ID
     * @param platform Platform string (e.g., "android")
     * @param sdkVersion SDK version string
     * @return AuthenticationResponse on success
     * @throws Exception on failure
     */
    fun authenticate(
        apiKey: String,
        baseUrl: String,
        deviceId: String,
        platform: String = "android",
        sdkVersion: String = "0.1.0"
    ): AuthenticationResponse {
        // Store config for future refresh/re-auth
        _baseUrl.set(baseUrl)
        _apiKey.set(apiKey)
        
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "🔐 Starting authentication with backend..."
        )
        
        // Build request body
        val request = AuthenticationRequest(
            apiKey = apiKey,
            deviceId = deviceId,
            platform = platform,
            sdkVersion = sdkVersion
        )
        val requestJson = json.encodeToString(AuthenticationRequest.serializer(), request)
        
        // Build full URL
        val fullUrl = baseUrl.trimEnd('/') + ENDPOINT_AUTHENTICATE

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Auth request to: $fullUrl"
        )
        
        // Make HTTP request
        val connection = URL(fullUrl).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            
            // Write request body
            OutputStreamWriter(connection.outputStream).use { writer ->
                writer.write(requestJson)
                writer.flush()
            }
            
            val responseCode = connection.responseCode
            
            if (responseCode == HttpURLConnection.HTTP_OK || responseCode == HttpURLConnection.HTTP_CREATED) {
                // Read response
                val responseBody = BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                    reader.readText()
                }
                
                // Parse response
                val response = json.decodeFromString(AuthenticationResponse.serializer(), responseBody)
                
                // Store in state
                storeAuthState(response)
                
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "✅ Authentication successful! Token expires in ${response.expiresIn}s"
                )
                
                return response
            } else {
                // Read error response
                val errorBody = try {
                    BufferedReader(InputStreamReader(connection.errorStream)).use { reader ->
                        reader.readText()
                    }
                } catch (e: Exception) {
                    "No error body"
                }
                
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "❌ Authentication failed: HTTP $responseCode - $errorBody"
                )
                
                throw Exception("Authentication failed: HTTP $responseCode - $errorBody")
            }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Refresh the access token using the refresh token.
     *
     * @param baseUrl The backend base URL
     * @return New access token
     * @throws Exception on failure
     */
    fun refreshAccessToken(baseUrl: String): String {
        val refreshToken = _refreshToken.get()
            ?: throw Exception("No refresh token available")
        val deviceId = _deviceId.get()
            ?: throw Exception("No device ID available")

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "🔄 Refreshing access token..."
        )
        
        // Build request body
        val request = RefreshTokenRequest(
            deviceId = deviceId,
            refreshToken = refreshToken
        )
        val requestJson = json.encodeToString(RefreshTokenRequest.serializer(), request)
        
        // Build full URL
        val fullUrl = baseUrl.trimEnd('/') + ENDPOINT_REFRESH
        
        // Make HTTP request
        val connection = URL(fullUrl).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            
            // Write request body
            OutputStreamWriter(connection.outputStream).use { writer ->
                writer.write(requestJson)
                writer.flush()
            }
            
            val responseCode = connection.responseCode
            
            if (responseCode == HttpURLConnection.HTTP_OK || responseCode == HttpURLConnection.HTTP_CREATED) {
                // Read response
                val responseBody = BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                    reader.readText()
                }
                
                // Parse response
                val response = json.decodeFromString(AuthenticationResponse.serializer(), responseBody)
                
                // Store in state
                storeAuthState(response)
                
        CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "✅ Token refresh successful!"
                )
                
                return response.accessToken
            } else {
                val errorBody = try {
                    BufferedReader(InputStreamReader(connection.errorStream)).use { reader ->
                        reader.readText()
                    }
            } catch (e: Exception) {
                    "No error body"
                }
                
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "❌ Token refresh failed: HTTP $responseCode - $errorBody"
                )
                
                throw Exception("Token refresh failed: HTTP $responseCode - $errorBody")
            }
        } finally {
            connection.disconnect()
        }
    }
    
    /**
     * Get a valid access token, refreshing if needed.
     *
     * @param baseUrl The backend base URL (needed for refresh)
     * @return Valid access token
     * @throws Exception if no valid token available
     */
    fun getValidAccessToken(baseUrl: String): String {
        // Check if current token is valid
        val currentToken = _accessToken.get()
        if (currentToken != null && !tokenNeedsRefresh) {
            return currentToken
        }
        
        // Try to refresh
        if (_refreshToken.get() != null) {
            return refreshAccessToken(baseUrl)
        }
        
        throw Exception("No valid access token - authentication required")
    }
    
    /**
     * Clear authentication state
     */
    fun clearAuth() {
        _accessToken.set(null)
        _refreshToken.set(null)
        _deviceId.set(null)
        _organizationId.set(null)
        _userId.set(null)
        _expiresAt.set(null)
        
        // Also clear from secure storage
        try {
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.accessToken", ByteArray(0))
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.refreshToken", ByteArray(0))
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to clear tokens from secure storage: ${e.message}"
            )
        }
        
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Authentication state cleared"
        )
    }

    /**
     * Store authentication state from response
     */
    private fun storeAuthState(response: AuthenticationResponse) {
        _accessToken.set(response.accessToken)
        _refreshToken.set(response.refreshToken)
        _deviceId.set(response.deviceId)
        _organizationId.set(response.organizationId)
        _userId.set(response.userId)
        
        // Calculate expiration time
        val expiresAt = System.currentTimeMillis() + (response.expiresIn * 1000L)
        _expiresAt.set(expiresAt)
        
        // Store in secure storage for persistence across app restarts
        try {
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.accessToken", response.accessToken.toByteArray(Charsets.UTF_8))
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.refreshToken", response.refreshToken.toByteArray(Charsets.UTF_8))
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.deviceId", response.deviceId.toByteArray(Charsets.UTF_8))
            response.userId?.let { 
                CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.userId", it.toByteArray(Charsets.UTF_8))
            }
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.organizationId", response.organizationId.toByteArray(Charsets.UTF_8))
            CppBridgePlatformAdapter.secureSetCallback("com.runanywhere.sdk.expiresAt", expiresAt.toString().toByteArray(Charsets.UTF_8))
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to store tokens in secure storage: ${e.message}"
            )
        }
    }

    /**
     * Restore authentication state from secure storage
     */
    fun restoreAuthState() {
        try {
            // Convert ByteArray to String for each stored value
            val accessTokenBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.accessToken")
            val refreshTokenBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.refreshToken")
            val deviceIdBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.deviceId")
            val userIdBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.userId")
            val organizationIdBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.organizationId")
            val expiresAtBytes = CppBridgePlatformAdapter.secureGetCallback("com.runanywhere.sdk.expiresAt")
            
            val accessToken = accessTokenBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            val refreshToken = refreshTokenBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            val deviceId = deviceIdBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            val userId = userIdBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            val organizationId = organizationIdBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            val expiresAtStr = expiresAtBytes?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
            
            if (accessToken != null && refreshToken != null) {
                _accessToken.set(accessToken)
                _refreshToken.set(refreshToken)
                _deviceId.set(deviceId)
                _userId.set(userId)
                _organizationId.set(organizationId)
                expiresAtStr?.toLongOrNull()?.let { _expiresAt.set(it) }
                
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "Restored authentication state from secure storage"
                )
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to restore auth state: ${e.message}"
            )
        }
    }
}
