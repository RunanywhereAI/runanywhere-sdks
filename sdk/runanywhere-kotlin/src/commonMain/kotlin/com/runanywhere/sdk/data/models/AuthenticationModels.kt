package com.runanywhere.sdk.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Authentication data models
 * One-to-one translation from iOS Swift models to Kotlin
 */

@Serializable
data class AuthenticationRequest(
    @SerialName("api_key")
    val apiKey: String,
    @SerialName("device_id")
    val deviceId: String?,
    @SerialName("sdk_version")
    val sdkVersion: String,
    val platform: String,
    @SerialName("platform_version")
    val platformVersion: String,
    @SerialName("app_identifier")
    val appIdentifier: String,
)

@Serializable
data class AuthenticationResponse(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String?,
    @SerialName("expires_in")
    val expiresIn: Int,
    @SerialName("token_type")
    val tokenType: String,
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("organization_id")
    val organizationId: String,
    @SerialName("user_id")
    val userId: String? = null, // Make nullable with default value
    @SerialName("token_expires_at")
    val tokenExpiresAt: Long? = null, // Make nullable - backend may not return this
)

@Serializable
data class RefreshTokenRequest(
    @SerialName("refresh_token")
    val refreshToken: String,
    @SerialName("grant_type")
    val grantType: String = "refresh_token",
)

@Serializable
data class RefreshTokenResponse(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String?,
    @SerialName("expires_in")
    val expiresIn: Int,
    @SerialName("token_type")
    val tokenType: String,
)

@Serializable
data class DeviceRegistrationRequest(
    @SerialName("device_model")
    val deviceModel: String,
    @SerialName("device_name")
    val deviceName: String,
    @SerialName("operating_system")
    val operatingSystem: String,
    @SerialName("os_version")
    val osVersion: String,
    @SerialName("sdk_version")
    val sdkVersion: String,
    @SerialName("app_identifier")
    val appIdentifier: String,
    @SerialName("app_version")
    val appVersion: String,
    @SerialName("hardware_capabilities")
    val hardwareCapabilities: Map<String, String> = emptyMap(),
    @SerialName("privacy_settings")
    val privacySettings: Map<String, Boolean> = emptyMap(),
)

// DeviceRegistrationResponse moved to data/network/models/AuthModels.kt - use import from there

@Serializable
data class HealthCheckResponse(
    val status: String,
    val version: String,
    val timestamp: Long,
    val services: Map<String, String> = emptyMap(),
)

/**
 * Stored token data for keychain
 */
data class StoredTokens(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Long,
)
