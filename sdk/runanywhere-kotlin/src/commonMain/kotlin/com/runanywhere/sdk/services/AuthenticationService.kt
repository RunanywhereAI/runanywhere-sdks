package com.runanywhere.sdk.services

import com.runanywhere.sdk.config.SDKConfig
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.foundation.DeviceIdentity
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.HttpClient
import com.runanywhere.sdk.security.SecureStorage
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.SDKConstants
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * Service responsible for authentication and token management
 * Full parity with iOS AuthenticationService implementation
 */
class AuthenticationService(
    private val secureStorage: SecureStorage,
    private val httpClient: HttpClient,
) {
    private val logger = SDKLogger("AuthenticationService")
    private val json =
        Json {
            ignoreUnknownKeys = true
            coerceInputValues = true // Handle nulls for fields with default values
        }

    // Thread safety mutex (replaces actor pattern from iOS)
    private val mutex = Mutex()

    // Storage keys (matching iOS KeychainManager pattern)
    companion object {
        // Authentication tokens
        private const val KEY_ACCESS_TOKEN = "com.runanywhere.sdk.accessToken"
        private const val KEY_REFRESH_TOKEN = "com.runanywhere.sdk.refreshToken"
        private const val KEY_TOKEN_EXPIRES_AT = "com.runanywhere.sdk.tokenExpiresAt"

        // User identity fields from authentication response
        private const val KEY_DEVICE_ID = "com.runanywhere.sdk.deviceId"
        private const val KEY_ORGANIZATION_ID = "com.runanywhere.sdk.organizationId"
        private const val KEY_USER_ID = "com.runanywhere.sdk.userId"

        // Token buffer for refresh (1 minute like iOS)
        private const val TOKEN_REFRESH_BUFFER_MILLIS = 60_000L
    }

    // In-memory cache
    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var tokenExpiresAt: Long? = null

    // User identity cache
    private var deviceId: String? = null
    private var organizationId: String? = null
    private var userId: String? = null

    /**
     * Authenticate with the backend and obtain access token
     * Matches iOS AuthenticationService.authenticate(apiKey:) method
     */
    suspend fun authenticate(apiKey: String): AuthenticationResponse =
        mutex.withLock {
            val deviceId = DeviceIdentity.persistentUUID

            val request =
                AuthenticationRequest(
                    apiKey = apiKey,
                    deviceId = deviceId,
                    sdkVersion = SDKConstants.version,
                    platform = SDKConstants.platform,
                    platformVersion = getPlatformVersion(),
                    appIdentifier = getAppIdentifier(),
                )

            logger.debug("Authenticating with backend")
            logger.debug("API Key: ${apiKey.take(20)}...")
            logger.debug("Device ID: $deviceId")
            logger.debug("Platform: ${SDKConstants.platform}")
            logger.debug("Platform Version: ${getPlatformVersion()}")
            logger.debug("App Identifier: ${getAppIdentifier()}")

            try {
                val response = performAuthenticationRequest(request)

                // Store tokens in memory and secure storage
                this.accessToken = response.accessToken
                this.refreshToken = response.refreshToken
                this.tokenExpiresAt = getCurrentTimeMillis() + (response.expiresIn * 1000)

                // Store user identity fields
                this.deviceId = response.deviceId
                this.organizationId = response.organizationId
                this.userId = response.userId // Can be null

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
    suspend fun getAccessToken(): String =
        mutex.withLock {
            // Check if token exists and is valid (with buffer like iOS)
            val currentTime = getCurrentTimeMillis()
            if (accessToken != null &&
                tokenExpiresAt != null &&
                tokenExpiresAt!! > currentTime + TOKEN_REFRESH_BUFFER_MILLIS
            ) {
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
    suspend fun healthCheck(): HealthCheckResponse =
        mutex.withLock {
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
     * Register device with backend (lazy registration pattern from Swift SDK)
     * Matches Swift SDK's AuthenticationService.registerDevice() method
     */
    suspend fun registerDevice(): DeviceRegistrationResponse =
        mutex.withLock {
            logger.debug("Registering device with backend")

            try {
                // Get access token (authenticate if needed)
                val token = getAccessToken()

                // Collect device information
                val deviceInfo = PlatformUtils.getDeviceInfo()

                // Create registration request
                val request =
                    DeviceRegistrationRequest(
                        deviceModel = deviceInfo["deviceModel"] ?: "unknown",
                        deviceName = deviceInfo["deviceName"] ?: "unknown",
                        operatingSystem = SDKConstants.platform,
                        osVersion = deviceInfo["os_version"] ?: "unknown",
                        sdkVersion = SDKConstants.version,
                        appIdentifier = getAppIdentifier(),
                        appVersion = PlatformUtils.getAppVersion() ?: "unknown",
                        hardwareCapabilities = deviceInfo.filterValues { it.isNotEmpty() },
                        privacySettings = emptyMap(),
                    )
                val requestBody = json.encodeToString(DeviceRegistrationRequest.serializer(), request)

                // Make API call
                val response =
                    httpClient.post(
                        url = SDKConfig.getApiUrl("/api/v1/devices/register"),
                        body = requestBody.encodeToByteArray(),
                        headers =
                            mapOf(
                                "Authorization" to "Bearer $token",
                                "Content-Type" to "application/json",
                                "X-SDK-Client" to "RunAnywhereKotlinSDK",
                                "X-SDK-Version" to SDKConstants.version,
                                "X-Platform" to SDKConstants.platform,
                            ),
                    )

                if (!response.isSuccessful) {
                    throw SDKError.NetworkError("Device registration failed with status: ${response.statusCode}")
                }

                val registrationResponse = json.decodeFromString<DeviceRegistrationResponse>(response.bodyAsString())
                logger.info("Device registered successfully: ${registrationResponse.deviceId}")

                return registrationResponse
            } catch (e: Exception) {
                logger.error("Device registration failed", e)
                throw SDKError.NetworkError("Device registration failed: ${e.message}")
            }
        }

    /**
     * Check if authenticated
     * Matches iOS AuthenticationService.isAuthenticated() method
     */
    fun isAuthenticated(): Boolean = accessToken != null

    /**
     * Get stored device ID
     * Matches iOS AuthenticationService.getDeviceId() method
     */
    fun getDeviceId(): String? = deviceId

    /**
     * Get stored organization ID
     * Matches iOS AuthenticationService.getOrganizationId() method
     */
    fun getOrganizationId(): String? = organizationId

    /**
     * Get stored user ID
     * Matches iOS AuthenticationService.getUserId() method
     */
    fun getUserId(): String? = userId

    /**
     * Clear authentication state
     * Matches iOS AuthenticationService.clearAuthentication() method
     */
    suspend fun clearAuthentication() =
        mutex.withLock {
            accessToken = null
            refreshToken = null
            tokenExpiresAt = null
            deviceId = null
            organizationId = null
            userId = null

            // Clear from secure storage
            try {
                secureStorage.removeSecure(KEY_ACCESS_TOKEN)
                secureStorage.removeSecure(KEY_REFRESH_TOKEN)
                secureStorage.removeSecure(KEY_TOKEN_EXPIRES_AT)
                secureStorage.removeSecure(KEY_DEVICE_ID)
                secureStorage.removeSecure(KEY_ORGANIZATION_ID)
                secureStorage.removeSecure(KEY_USER_ID)

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
    suspend fun loadStoredTokens() =
        mutex.withLock {
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

                // Load user identity fields
                val storedDeviceId = secureStorage.getSecureString(KEY_DEVICE_ID)
                if (storedDeviceId != null) {
                    this.deviceId = storedDeviceId
                    logger.debug("Loaded stored device ID from secure storage")
                }

                val storedOrganizationId = secureStorage.getSecureString(KEY_ORGANIZATION_ID)
                if (storedOrganizationId != null) {
                    this.organizationId = storedOrganizationId
                    logger.debug("Loaded stored organization ID from secure storage")
                }

                val storedUserId = secureStorage.getSecureString(KEY_USER_ID)
                if (storedUserId != null) {
                    this.userId = storedUserId
                    logger.debug("Loaded stored user ID from secure storage")
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
        val url = SDKConfig.getAuthUrl("/sdk/authenticate")

        logger.debug("Authenticating with backend")

        val response =
            httpClient.post(
                url = url,
                body = requestBody.encodeToByteArray(),
                headers =
                    mapOf(
                        "Content-Type" to "application/json",
                        "X-SDK-Client" to "RunAnywhereKotlinSDK",
                        "X-SDK-Version" to SDKConstants.version,
                        "X-Platform" to SDKConstants.platform,
                    ),
            )

        if (!response.isSuccessful) {
            val responseBody =
                try {
                    response.bodyAsString()
                } catch (e: Exception) {
                    "Unable to read response body"
                }
            val errorMessage = "Authentication failed with status: ${response.statusCode}, Response: $responseBody"
            logger.error(errorMessage)
            throw SDKError.AuthenticationError("Authentication failed with status: ${response.statusCode}")
        }

        return json.decodeFromString<AuthenticationResponse>(response.bodyAsString())
    }

    /**
     * Refresh access token using refresh token
     */
    private suspend fun refreshAccessToken(): String {
        val currentRefreshToken =
            refreshToken
                ?: throw SDKError.InvalidAPIKey("No refresh token available")

        logger.debug("Refreshing access token")

        try {
            val refreshRequest = RefreshTokenRequest(refreshToken = currentRefreshToken)
            val requestBody = json.encodeToString(RefreshTokenRequest.serializer(), refreshRequest)

            val response =
                httpClient.post(
                    url = SDKConfig.getAuthUrl("/sdk/refresh"),
                    body = requestBody.encodeToByteArray(),
                    headers =
                        mapOf(
                            "Content-Type" to "application/json",
                            "X-SDK-Client" to "RunAnywhereKotlinSDK",
                            "X-SDK-Version" to SDKConstants.version,
                            "X-Platform" to SDKConstants.platform,
                        ),
                )

            if (!response.isSuccessful) {
                val errorMessage = "Token refresh failed with status: ${response.statusCode}"
                logger.error(errorMessage)
                throw SDKError.AuthenticationError(errorMessage)
            }

            val refreshResponse = json.decodeFromString<RefreshTokenResponse>(response.bodyAsString())

            // Update tokens in memory
            this.accessToken = refreshResponse.accessToken
            this.refreshToken = refreshResponse.refreshToken ?: currentRefreshToken
            this.tokenExpiresAt = getCurrentTimeMillis() + (refreshResponse.expiresIn * 1000)

            // Store updated tokens in secure storage
            storeRefreshTokensInSecureStorage(refreshResponse)

            logger.info("Token refresh successful")
            return refreshResponse.accessToken
        } catch (e: Exception) {
            logger.error("Token refresh failed", e)
            throw SDKError.AuthenticationError("Token refresh failed: ${e.message}")
        }
    }

    /**
     * Perform health check request
     */
    private suspend fun performHealthCheckRequest(accessToken: String): HealthCheckResponse {
        val response =
            httpClient.get(
                url = SDKConfig.getApiUrl("/health"),
                headers =
                    mapOf(
                        "Authorization" to "Bearer $accessToken",
                        "Content-Type" to "application/json",
                        "X-SDK-Client" to "RunAnywhereKotlinSDK",
                        "X-SDK-Version" to SDKConstants.version,
                        "X-Platform" to SDKConstants.platform,
                    ),
            )

        if (!response.isSuccessful) {
            throw SDKError.NetworkError("Health check failed with status: ${response.statusCode}")
        }

        return json.decodeFromString<HealthCheckResponse>(response.bodyAsString())
    }

    /**
     * Get platform version (JVM version, Android API level, etc.)
     */
    private fun getPlatformVersion(): String =
        try {
            // Use PlatformUtils to get platform-specific version information
            val deviceInfo = PlatformUtils.getDeviceInfo()
            deviceInfo["os_version"] ?: deviceInfo["platform_version"] ?: PlatformUtils.getOSVersion()
        } catch (e: Exception) {
            // Fallback to SDK platform constant
            "Unknown"
        }

    /**
     * Get app identifier (bundle ID, package name, etc.)
     */
    private fun getAppIdentifier(): String =
        try {
            // Try to get app version/identifier from platform utils
            PlatformUtils.getAppVersion() ?: "com.runanywhere.sdk.unknown"
        } catch (e: Exception) {
            // Fallback to default SDK identifier
            "com.runanywhere.sdk.unknown"
        }

    /**
     * Store tokens in secure storage for persistence
     * Matches iOS storeTokensInKeychain method
     */
    private suspend fun storeTokensInSecureStorage(response: AuthenticationResponse) {
        try {
            secureStorage.setSecureString(KEY_ACCESS_TOKEN, response.accessToken)
            response.refreshToken?.let { refreshToken ->
                secureStorage.setSecureString(KEY_REFRESH_TOKEN, refreshToken)
            }
            tokenExpiresAt?.let { expiresAt ->
                secureStorage.setSecureString(KEY_TOKEN_EXPIRES_AT, expiresAt.toString())
            }

            // Store user identity fields
            secureStorage.setSecureString(KEY_DEVICE_ID, response.deviceId)
            secureStorage.setSecureString(KEY_ORGANIZATION_ID, response.organizationId)
            response.userId?.let { userId ->
                secureStorage.setSecureString(KEY_USER_ID, userId)
            }
        } catch (e: Exception) {
            logger.error("Failed to store tokens in secure storage", e)
            throw SDKError.FileSystemError("Failed to store tokens: ${e.message}")
        }
    }

    /**
     * Store refresh token response in secure storage
     * Used when only token refresh response is available (not full auth response)
     */
    private suspend fun storeRefreshTokensInSecureStorage(response: RefreshTokenResponse) {
        try {
            secureStorage.setSecureString(KEY_ACCESS_TOKEN, response.accessToken)
            response.refreshToken?.let { refreshToken ->
                secureStorage.setSecureString(KEY_REFRESH_TOKEN, refreshToken)
            }
            tokenExpiresAt?.let { expiresAt ->
                secureStorage.setSecureString(KEY_TOKEN_EXPIRES_AT, expiresAt.toString())
            }
        } catch (e: Exception) {
            logger.error("Failed to store refresh tokens in secure storage", e)
            throw SDKError.FileSystemError("Failed to store refresh tokens: ${e.message}")
        }
    }
}
