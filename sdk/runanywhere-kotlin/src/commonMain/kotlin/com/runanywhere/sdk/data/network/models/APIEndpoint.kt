package com.runanywhere.sdk.data.network.models

/**
 * API endpoints - equivalent to iOS APIEndpoint
 */
enum class APIEndpoint(val url: String) {
    // Authentication & Health
    authenticate("/api/v1/auth/sdk/authenticate"),
    refreshToken("/api/v1/auth/sdk/refresh"),
    healthCheck("/api/v1/health"),

    // Device management
    registerDevice("/api/v1/devices/register"),
    deviceInfo("/api/v1/devices/info"),

    // Core endpoints
    configuration("/api/v1/configuration"),
    telemetry("/api/v1/telemetry"),
    models("/api/v1/models"),
    history("/api/v1/history"),
    preferences("/api/v1/preferences")
}
