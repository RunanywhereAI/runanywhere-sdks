/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Auth extension for CppBridge.
 * Provides authentication flow callbacks for C++ core.
 *
 * Follows iOS CppBridge+Auth.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Authentication bridge that provides authentication flow callbacks for C++ core.
 *
 * The C++ core needs authentication state and credentials for:
 * - API key validation
 * - Token-based authentication
 * - Access control for model downloads
 * - Service authorization
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeAuth {

    /**
     * Authentication status constants matching C++ RAC_AUTH_STATUS_* values.
     */
    object AuthStatus {
        /** Not authenticated */
        const val NOT_AUTHENTICATED = 0

        /** Authentication in progress */
        const val AUTHENTICATING = 1

        /** Successfully authenticated */
        const val AUTHENTICATED = 2

        /** Authentication failed */
        const val FAILED = 3

        /** Authentication expired (token expired) */
        const val EXPIRED = 4

        /**
         * Get a human-readable name for the auth status.
         */
        fun getName(status: Int): String = when (status) {
            NOT_AUTHENTICATED -> "NOT_AUTHENTICATED"
            AUTHENTICATING -> "AUTHENTICATING"
            AUTHENTICATED -> "AUTHENTICATED"
            FAILED -> "FAILED"
            EXPIRED -> "EXPIRED"
            else -> "UNKNOWN($status)"
        }
    }

    /**
     * Authentication error codes matching C++ RAC_AUTH_ERROR_* values.
     */
    object AuthErrorCode {
        /** No error */
        const val NONE = 0

        /** Invalid API key */
        const val INVALID_API_KEY = 1

        /** API key expired */
        const val API_KEY_EXPIRED = 2

        /** Invalid token */
        const val INVALID_TOKEN = 3

        /** Token expired */
        const val TOKEN_EXPIRED = 4

        /** Unauthorized access */
        const val UNAUTHORIZED = 5

        /** Network error during authentication */
        const val NETWORK_ERROR = 6

        /** Server error during authentication */
        const val SERVER_ERROR = 7

        /** Unknown error */
        const val UNKNOWN = 99

        /**
         * Get a human-readable name for the error code.
         */
        fun getName(code: Int): String = when (code) {
            NONE -> "NONE"
            INVALID_API_KEY -> "INVALID_API_KEY"
            API_KEY_EXPIRED -> "API_KEY_EXPIRED"
            INVALID_TOKEN -> "INVALID_TOKEN"
            TOKEN_EXPIRED -> "TOKEN_EXPIRED"
            UNAUTHORIZED -> "UNAUTHORIZED"
            NETWORK_ERROR -> "NETWORK_ERROR"
            SERVER_ERROR -> "SERVER_ERROR"
            UNKNOWN -> "UNKNOWN"
            else -> "UNKNOWN($code)"
        }
    }

    /**
     * Token type constants.
     */
    object TokenType {
        /** Access token for API calls */
        const val ACCESS = 0

        /** Refresh token for obtaining new access tokens */
        const val REFRESH = 1

        /** ID token for user identification */
        const val ID = 2
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var authStatus: Int = AuthStatus.NOT_AUTHENTICATED

    @Volatile
    private var apiKey: String? = null

    @Volatile
    private var accessToken: String? = null

    @Volatile
    private var refreshToken: String? = null

    @Volatile
    private var tokenExpirationMs: Long = 0

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeAuth"

    /**
     * Secure storage keys for auth credentials.
     */
    private const val API_KEY_STORAGE_KEY = "runanywhere_api_key"
    private const val ACCESS_TOKEN_STORAGE_KEY = "runanywhere_access_token"
    private const val REFRESH_TOKEN_STORAGE_KEY = "runanywhere_refresh_token"
    private const val TOKEN_EXPIRATION_STORAGE_KEY = "runanywhere_token_expiration"

    /**
     * Optional listener for authentication events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var authListener: AuthListener? = null

    /**
     * Optional provider for custom authentication logic.
     * Set this to implement custom authentication flows.
     */
    @Volatile
    var authProvider: AuthProvider? = null

    /**
     * Listener interface for authentication events.
     */
    interface AuthListener {
        /**
         * Called when authentication status changes.
         *
         * @param previousStatus The previous auth status
         * @param newStatus The new auth status
         */
        fun onAuthStatusChanged(previousStatus: Int, newStatus: Int)

        /**
         * Called when authentication succeeds.
         */
        fun onAuthSuccess()

        /**
         * Called when authentication fails.
         *
         * @param errorCode The error code (see [AuthErrorCode])
         * @param errorMessage The error message
         */
        fun onAuthFailure(errorCode: Int, errorMessage: String)

        /**
         * Called when a token is refreshed.
         *
         * @param tokenType The type of token (see [TokenType])
         */
        fun onTokenRefreshed(tokenType: Int)

        /**
         * Called when a token expires.
         *
         * @param tokenType The type of token (see [TokenType])
         */
        fun onTokenExpired(tokenType: Int)
    }

    /**
     * Provider interface for custom authentication logic.
     *
     * Implement this to provide custom API key validation or token refresh logic.
     */
    interface AuthProvider {
        /**
         * Validate an API key.
         *
         * @param apiKey The API key to validate
         * @return true if the API key is valid, false otherwise
         */
        fun validateApiKey(apiKey: String): Boolean

        /**
         * Refresh the access token using the refresh token.
         *
         * @param refreshToken The refresh token
         * @return The new access token, or null if refresh failed
         */
        fun refreshAccessToken(refreshToken: String): String?

        /**
         * Get the token expiration time in milliseconds.
         *
         * @param token The token to check
         * @return The expiration time in milliseconds since epoch, or 0 if unknown
         */
        fun getTokenExpirationMs(token: String): Long
    }

    /**
     * Register the auth callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Load saved credentials from secure storage
            loadSavedCredentials()

            // Register the auth callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetAuthCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Auth callbacks registered. Status: ${AuthStatus.getName(authStatus)}"
            )
        }
    }

    /**
     * Check if the auth callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the current authentication status.
     */
    fun getStatus(): Int = authStatus

    /**
     * Check if the SDK is authenticated.
     */
    fun isAuthenticated(): Boolean = authStatus == AuthStatus.AUTHENTICATED

    // ========================================================================
    // AUTH CALLBACKS
    // ========================================================================

    /**
     * Get the API key callback.
     *
     * Returns the currently configured API key for authentication.
     *
     * @return The API key, or null if not set
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getApiKeyCallback(): String? {
        return apiKey
    }

    /**
     * Get the access token callback.
     *
     * Returns the current access token for API authorization.
     *
     * @return The access token, or null if not authenticated
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAccessTokenCallback(): String? {
        // Check if token is expired
        if (accessToken != null && tokenExpirationMs > 0) {
            val now = System.currentTimeMillis()
            if (now >= tokenExpirationMs) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Access token expired, attempting refresh"
                )
                // Try to refresh the token
                refreshTokenIfNeeded()
            }
        }
        return accessToken
    }

    /**
     * Get the refresh token callback.
     *
     * Returns the refresh token for obtaining new access tokens.
     *
     * @return The refresh token, or null if not available
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getRefreshTokenCallback(): String? {
        return refreshToken
    }

    /**
     * Get the authentication status callback.
     *
     * @return The current auth status (see [AuthStatus])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAuthStatusCallback(): Int {
        return authStatus
    }

    /**
     * Check if authenticated callback.
     *
     * @return true if currently authenticated, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isAuthenticatedCallback(): Boolean {
        return authStatus == AuthStatus.AUTHENTICATED
    }

    /**
     * Set authentication status callback.
     *
     * Called by C++ core when authentication status changes.
     *
     * @param status The new auth status (see [AuthStatus])
     * @param errorCode Error code if status is FAILED (see [AuthErrorCode])
     * @param errorMessage Error message if status is FAILED
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setAuthStatusCallback(status: Int, errorCode: Int, errorMessage: String?) {
        val previousStatus = authStatus
        authStatus = status

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Auth status changed: ${AuthStatus.getName(previousStatus)} -> ${AuthStatus.getName(status)}"
        )

        // Notify listener
        try {
            authListener?.onAuthStatusChanged(previousStatus, status)

            when (status) {
                AuthStatus.AUTHENTICATED -> {
                    authListener?.onAuthSuccess()
                }
                AuthStatus.FAILED -> {
                    authListener?.onAuthFailure(
                        errorCode,
                        errorMessage ?: "Authentication failed"
                    )
                }
                AuthStatus.EXPIRED -> {
                    authListener?.onTokenExpired(TokenType.ACCESS)
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in auth listener: ${e.message}"
            )
        }
    }

    /**
     * Set token callback.
     *
     * Called by C++ core when a token is received or refreshed.
     *
     * @param tokenType The type of token (see [TokenType])
     * @param token The token value
     * @param expirationMs Token expiration in milliseconds since epoch
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setTokenCallback(tokenType: Int, token: String, expirationMs: Long) {
        synchronized(lock) {
            when (tokenType) {
                TokenType.ACCESS -> {
                    accessToken = token
                    tokenExpirationMs = expirationMs
                    saveToSecureStorage(ACCESS_TOKEN_STORAGE_KEY, token)
                    saveToSecureStorage(TOKEN_EXPIRATION_STORAGE_KEY, expirationMs.toString())
                }
                TokenType.REFRESH -> {
                    refreshToken = token
                    saveToSecureStorage(REFRESH_TOKEN_STORAGE_KEY, token)
                }
            }
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Token set: type=${tokenType}, expires=${expirationMs}"
        )

        // Notify listener
        try {
            authListener?.onTokenRefreshed(tokenType)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in auth listener onTokenRefreshed: ${e.message}"
            )
        }
    }

    /**
     * Validate API key callback.
     *
     * Called by C++ core to validate an API key.
     *
     * @param key The API key to validate
     * @return true if the API key is valid, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun validateApiKeyCallback(key: String): Boolean {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Validating API key"
        )

        // Use custom provider if available
        val provider = authProvider
        if (provider != null) {
            return try {
                provider.validateApiKey(key)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Error validating API key: ${e.message}"
                )
                false
            }
        }

        // Default validation: non-empty key with minimum length
        return key.isNotBlank() && key.length >= 8
    }

    /**
     * Clear credentials callback.
     *
     * Called by C++ core to clear all stored credentials.
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearCredentialsCallback() {
        synchronized(lock) {
            apiKey = null
            accessToken = null
            refreshToken = null
            tokenExpirationMs = 0
            authStatus = AuthStatus.NOT_AUTHENTICATED

            // Clear from secure storage
            CppBridgePlatformAdapter.secureDeleteCallback(API_KEY_STORAGE_KEY)
            CppBridgePlatformAdapter.secureDeleteCallback(ACCESS_TOKEN_STORAGE_KEY)
            CppBridgePlatformAdapter.secureDeleteCallback(REFRESH_TOKEN_STORAGE_KEY)
            CppBridgePlatformAdapter.secureDeleteCallback(TOKEN_EXPIRATION_STORAGE_KEY)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Credentials cleared"
        )
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the auth callbacks with C++ core.
     *
     * Registers [getApiKeyCallback], [getAccessTokenCallback],
     * [getAuthStatusCallback], [setAuthStatusCallback], [setTokenCallback],
     * [validateApiKeyCallback], and [clearCredentialsCallback] with C++ core.
     *
     * C API: rac_auth_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetAuthCallbacks()

    /**
     * Native method to unset the auth callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_auth_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetAuthCallbacks()

    /**
     * Native method to authenticate with API key.
     *
     * @param apiKey The API key to authenticate with
     * @return 0 on success, error code on failure
     *
     * C API: rac_auth_authenticate_api_key(api_key)
     */
    @JvmStatic
    external fun nativeAuthenticateApiKey(apiKey: String): Int

    /**
     * Native method to refresh the access token.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_auth_refresh_token()
     */
    @JvmStatic
    external fun nativeRefreshToken(): Int

    /**
     * Native method to logout and clear credentials.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_auth_logout()
     */
    @JvmStatic
    external fun nativeLogout(): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the auth callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetAuthCallbacks()

            authListener = null
            authProvider = null
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Set the API key for authentication.
     *
     * This stores the API key and triggers authentication.
     *
     * @param key The API key to use
     */
    fun setApiKey(key: String) {
        synchronized(lock) {
            apiKey = key
            saveToSecureStorage(API_KEY_STORAGE_KEY, key)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "API key set"
        )
    }

    /**
     * Authenticate with the configured API key.
     *
     * @return true if authentication was triggered, false if no API key is set
     */
    fun authenticate(): Boolean {
        val key = apiKey ?: return false

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Starting authentication"
        )

        authStatus = AuthStatus.AUTHENTICATING

        // Notify listener
        try {
            authListener?.onAuthStatusChanged(AuthStatus.NOT_AUTHENTICATED, AuthStatus.AUTHENTICATING)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in auth listener: ${e.message}"
            )
        }

        // TODO: Call native authentication
        // val result = nativeAuthenticateApiKey(key)
        // return result == 0

        // For now, simulate successful authentication if API key is valid
        val isValid = validateApiKeyCallback(key)
        if (isValid) {
            setAuthStatusCallback(AuthStatus.AUTHENTICATED, AuthErrorCode.NONE, null)
        } else {
            setAuthStatusCallback(AuthStatus.FAILED, AuthErrorCode.INVALID_API_KEY, "Invalid API key")
        }

        return isValid
    }

    /**
     * Logout and clear all credentials.
     */
    fun logout() {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Logging out"
        )

        // TODO: Call native logout
        // nativeLogout()

        clearCredentialsCallback()
    }

    /**
     * Refresh the access token if needed.
     *
     * @return true if token was refreshed or still valid, false if refresh failed
     */
    fun refreshTokenIfNeeded(): Boolean {
        val refresh = refreshToken ?: return false

        // Check if token is expired
        val now = System.currentTimeMillis()
        if (tokenExpirationMs > 0 && now < tokenExpirationMs) {
            // Token is still valid
            return true
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Refreshing access token"
        )

        // Use custom provider if available
        val provider = authProvider
        if (provider != null) {
            return try {
                val newToken = provider.refreshAccessToken(refresh)
                if (newToken != null) {
                    val expiration = provider.getTokenExpirationMs(newToken)
                    setTokenCallback(TokenType.ACCESS, newToken, expiration)
                    true
                } else {
                    setAuthStatusCallback(
                        AuthStatus.EXPIRED,
                        AuthErrorCode.TOKEN_EXPIRED,
                        "Failed to refresh token"
                    )
                    false
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Error refreshing token: ${e.message}"
                )
                false
            }
        }

        // TODO: Call native token refresh
        // val result = nativeRefreshToken()
        // return result == 0

        return false
    }

    /**
     * Get the token expiration time.
     *
     * @return Token expiration time in milliseconds since epoch, or 0 if unknown
     */
    fun getTokenExpirationMs(): Long = tokenExpirationMs

    /**
     * Check if the access token is expired.
     *
     * @return true if token is expired or not set, false if valid
     */
    fun isTokenExpired(): Boolean {
        if (accessToken == null) return true
        if (tokenExpirationMs <= 0) return false
        return System.currentTimeMillis() >= tokenExpirationMs
    }

    /**
     * Load saved credentials from secure storage.
     */
    private fun loadSavedCredentials() {
        synchronized(lock) {
            // Load API key
            val savedApiKey = loadFromSecureStorage(API_KEY_STORAGE_KEY)
            if (savedApiKey != null) {
                apiKey = savedApiKey
            }

            // Load access token
            val savedAccessToken = loadFromSecureStorage(ACCESS_TOKEN_STORAGE_KEY)
            if (savedAccessToken != null) {
                accessToken = savedAccessToken
            }

            // Load refresh token
            val savedRefreshToken = loadFromSecureStorage(REFRESH_TOKEN_STORAGE_KEY)
            if (savedRefreshToken != null) {
                refreshToken = savedRefreshToken
            }

            // Load token expiration
            val savedExpiration = loadFromSecureStorage(TOKEN_EXPIRATION_STORAGE_KEY)
            if (savedExpiration != null) {
                try {
                    tokenExpirationMs = savedExpiration.toLong()
                } catch (e: NumberFormatException) {
                    tokenExpirationMs = 0
                }
            }

            // Set initial status based on saved credentials
            if (accessToken != null && !isTokenExpired()) {
                authStatus = AuthStatus.AUTHENTICATED
            } else if (apiKey != null) {
                authStatus = AuthStatus.NOT_AUTHENTICATED
            }
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Loaded saved credentials. HasApiKey=${apiKey != null}, HasToken=${accessToken != null}"
        )
    }

    /**
     * Save a value to secure storage.
     */
    private fun saveToSecureStorage(key: String, value: String) {
        try {
            CppBridgePlatformAdapter.secureSetCallback(key, value.toByteArray(Charsets.UTF_8))
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to save to secure storage: ${e.message}"
            )
        }
    }

    /**
     * Load a value from secure storage.
     */
    private fun loadFromSecureStorage(key: String): String? {
        return try {
            val bytes = CppBridgePlatformAdapter.secureGetCallback(key)
            bytes?.let { String(it, Charsets.UTF_8) }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to load from secure storage: ${e.message}"
            )
            null
        }
    }

    /**
     * Get authorization header value for HTTP requests.
     *
     * Returns "Bearer <token>" if authenticated with access token,
     * or "ApiKey <key>" if using API key authentication.
     *
     * @return The authorization header value, or null if not authenticated
     */
    fun getAuthorizationHeader(): String? {
        val token = accessToken
        if (token != null) {
            return "Bearer $token"
        }

        val key = apiKey
        if (key != null) {
            return "ApiKey $key"
        }

        return null
    }
}
