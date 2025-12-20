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

@Serializable
data class DeviceRegistrationResponse(
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("registration_status")
    val registrationStatus: String,
    @SerialName("created_at")
    val createdAt: Long,
    @SerialName("capabilities_verified")
    val capabilitiesVerified: Boolean = false,
)

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

/**
 * SDK Error extensions matching iOS pattern
 */
// Localized error description matching iOS pattern
val SDKError.errorDescription: String
    get() = message ?: "Unknown error"

val SDKError.recoverySuggestion: String
    get() =
        when (this) {
            is SDKError.NotInitialized -> "Call RunAnywhere.initialize() first"
            is SDKError.InvalidAPIKey -> "Check your API key and ensure it's valid"
            is SDKError.AuthenticationError -> "Verify your API key and network connection"
            is SDKError.NetworkError -> "Check your internet connection and try again"
            is SDKError.ConfigurationError -> "Check your configuration parameters"
            is SDKError.ModelNotFound -> "Ensure the model is available or download it first"
            is SDKError.ModelLoadingFailed -> "Check available memory and model file integrity"
            is SDKError.FileSystemError -> "Check storage permissions and available space"
            is SDKError.FileNotFound -> "Check if the file exists"
            is SDKError.InitializationFailed -> "Check initialization parameters"
            is SDKError.ModelDownloadFailed -> "Check network and retry download"
            is SDKError.InvalidConfiguration -> "Fix configuration settings"
            is SDKError.RuntimeError -> "Check runtime environment"
            is SDKError.ComponentNotAvailable -> "Ensure component is initialized"
            is SDKError.ValidationError -> "Check input validation"
            is SDKError.InvalidInput -> "Provide valid input"
            is SDKError.TranscriptionFailed -> "Check audio input and model"
            is SDKError.LoadingFailed -> "Check resource availability"
            else -> "Check error details and retry"
        }
