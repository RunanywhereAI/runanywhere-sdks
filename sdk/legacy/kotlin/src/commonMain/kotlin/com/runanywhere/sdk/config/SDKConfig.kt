package com.runanywhere.sdk.config

/**
 * SDK Configuration constants
 *
 * IMPORTANT: Production URLs must be provided via environment variables
 * or SDK initialization parameters. Never hardcode production URLs in
 * open source code.
 */
object SDKConfig {
    /**
     * Base URL - must be provided at runtime
     * Set via RunAnywhere.initialize(baseURL = "your-url")
     * or environment variable RUNANYWHERE_API_URL
     */
    var baseURL: String = ""
        internal set

    /**
     * API version
     */
    const val API_VERSION = "v1"

    /**
     * SDK version
     */
    const val SDK_VERSION = "0.1.0"

    /**
     * Default timeout in milliseconds
     */
    const val DEFAULT_TIMEOUT_MS = 30000L

    /**
     * Token refresh buffer in milliseconds (1 minute before expiry)
     */
    const val TOKEN_REFRESH_BUFFER_MS = 60000L

    /**
     * Initialize the SDK configuration
     */
    fun initialize(url: String?) {
        baseURL = url
            ?: System.getenv("RUNANYWHERE_API_URL")
            ?: throw IllegalArgumentException("API URL must be provided via parameter or RUNANYWHERE_API_URL environment variable")
    }

    /**
     * Get full API URL for an endpoint
     */
    fun getApiUrl(endpoint: String): String {
        requireNotNull(baseURL.isNotEmpty()) { "SDK not configured. Call RunAnywhere.initialize() first." }
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$baseURL/api/$API_VERSION$cleanEndpoint"
    }

    /**
     * Get authentication URL
     */
    fun getAuthUrl(endpoint: String): String {
        requireNotNull(baseURL.isNotEmpty()) { "SDK not configured. Call RunAnywhere.initialize() first." }
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$baseURL/api/$API_VERSION/auth$cleanEndpoint"
    }

    /**
     * Get device URL
     */
    fun getDeviceUrl(endpoint: String): String {
        requireNotNull(baseURL.isNotEmpty()) { "SDK not configured. Call RunAnywhere.initialize() first." }
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$baseURL/api/$API_VERSION/devices$cleanEndpoint"
    }
}
