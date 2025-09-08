package com.runanywhere.sdk.data.network.models

/**
 * API endpoints - equivalent to iOS APIEndpoint
 */
enum class APIEndpoint(val url: String) {
    // Authentication & Health
    AUTHENTICATE("/v1/auth/token"),
    HEALTH_CHECK("/v1/health"),

    // Core endpoints
    CONFIGURATION("/v1/configuration"),
    TELEMETRY("/v1/telemetry"),
    MODELS("/v1/models"),
    DEVICE_INFO("/v1/device"),
    GENERATION_HISTORY("/v1/history"),
    USER_PREFERENCES("/v1/preferences")
}
