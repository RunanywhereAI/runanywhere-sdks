package com.runanywhere.sdk.data.network.models

/**
 * API endpoints - equivalent to iOS APIEndpoint
 * Matches Swift SDK APIEndpoint.swift exactly
 */
enum class APIEndpoint(val url: String) {
    // Authentication & Health
    authenticate("/api/v1/auth/sdk/authenticate"),
    refreshToken("/api/v1/auth/sdk/refresh"),
    healthCheck("/api/v1/health"),

    // Device management
    registerDevice("/api/v1/devices/register"),
    deviceInfo("/api/v1/devices/info"),
    devDeviceRegistration("/api/v1/devices/register/dev"),

    // Analytics endpoints (production)
    /**
     * POST /api/v1/sdk/telemetry
     * Submit batch telemetry events (production)
     * Matches Swift SDK: APIEndpoint.telemetry
     */
    telemetry("/api/v1/sdk/telemetry"),

    /**
     * POST /api/v1/analytics/dev
     * Submit development analytics to Supabase
     * Matches Swift SDK: APIEndpoint.devAnalytics
     */
    devAnalytics("/api/v1/analytics/dev"),

    // Core endpoints
    configuration("/api/v1/configuration"),
    models("/api/v1/models"),
    history("/api/v1/history"),
    preferences("/api/v1/preferences")
}
