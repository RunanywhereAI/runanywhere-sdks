package com.runanywhere.sdk.data.network.models

import com.runanywhere.sdk.utils.SDKConstants

/**
 * API endpoints - exactly matching iOS APIEndpoint.swift
 */
enum class APIEndpoint(
    val url: String,
) {
    // Authentication & Health (matches iOS exactly)
    authenticate("/api/v1/auth/sdk/authenticate"),
    refreshToken("/api/v1/auth/sdk/refresh"),
    healthCheck("/v1/health"), // Fixed: iOS uses /v1/health without /api prefix

    // Device management - Production/Staging (matches iOS exactly)
    deviceRegistration("/api/v1/devices/register"),
    deviceInfo("/api/v1/device"), // Fixed: iOS uses /device not /devices/info

    // Device management - Development (matches iOS Supabase REST format)
    devDeviceRegistration("/rest/v1/device_registrations"), // Fixed: Supabase REST format

    // Analytics endpoints (matches iOS exactly)
    /**
     * POST /api/v1/analytics
     * Submit analytics events (production/staging)
     * Matches iOS: APIEndpoint.analytics
     */
    analytics("/api/v1/analytics"),

    /**
     * POST /rest/v1/analytics_events
     * Submit development analytics to Supabase
     * Matches iOS: APIEndpoint.devAnalytics (Supabase REST format)
     */
    devAnalytics("/rest/v1/analytics_events"), // Fixed: Supabase REST format

    /**
     * POST /api/v1/sdk/telemetry
     * Submit batch telemetry events
     * Matches iOS: APIEndpoint.telemetry
     */
    telemetry("/api/v1/sdk/telemetry"),

    // Model management (matches iOS exactly)
    models("/api/v1/models"),

    // Core endpoints (matches iOS exactly)
    generationHistory("/api/v1/history"),
    userPreferences("/api/v1/preferences"),

    // KMP-specific (not in iOS, but useful for SDK configuration)
    configuration("/api/v1/configuration"),
    ;

    companion object {
        /**
         * Get the device registration endpoint based on environment
         * Matches iOS: APIEndpoint.deviceRegistrationEndpoint(for:)
         */
        fun deviceRegistrationEndpoint(environment: SDKConstants.Environment): APIEndpoint =
            when (environment) {
                SDKConstants.Environment.DEVELOPMENT -> devDeviceRegistration
                SDKConstants.Environment.STAGING,
                SDKConstants.Environment.PRODUCTION,
                -> deviceRegistration
            }

        /**
         * Get the analytics endpoint based on environment
         * Matches iOS: APIEndpoint.analyticsEndpoint(for:)
         */
        fun analyticsEndpoint(environment: SDKConstants.Environment): APIEndpoint =
            when (environment) {
                SDKConstants.Environment.DEVELOPMENT -> devAnalytics
                SDKConstants.Environment.STAGING,
                SDKConstants.Environment.PRODUCTION,
                -> analytics
            }

        /**
         * Get model assignments endpoint with query parameters
         * Matches iOS: APIEndpoint.modelAssignments(deviceType:platform:)
         */
        fun modelAssignments(deviceType: String, platform: String): String =
            "/api/v1/model-assignments/for-sdk?device_type=$deviceType&platform=$platform"
    }
}
