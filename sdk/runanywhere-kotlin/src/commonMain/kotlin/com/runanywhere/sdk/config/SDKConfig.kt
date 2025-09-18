package com.runanywhere.sdk.config

/**
 * SDK Configuration constants
 */
object SDKConfig {
    /**
     * Production API base URL
     */
    const val PRODUCTION_BASE_URL = "https://REDACTED_URL"

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
     * Get full API URL for an endpoint
     */
    fun getApiUrl(endpoint: String): String {
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$PRODUCTION_BASE_URL/api/$API_VERSION$cleanEndpoint"
    }

    /**
     * Get authentication URL
     */
    fun getAuthUrl(endpoint: String): String {
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$PRODUCTION_BASE_URL/api/$API_VERSION/auth$cleanEndpoint"
    }

    /**
     * Get device URL
     */
    fun getDeviceUrl(endpoint: String): String {
        val cleanEndpoint = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        return "$PRODUCTION_BASE_URL/api/$API_VERSION/devices$cleanEndpoint"
    }
}
