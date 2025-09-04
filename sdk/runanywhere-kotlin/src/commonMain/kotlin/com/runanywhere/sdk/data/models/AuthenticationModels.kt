package com.runanywhere.sdk.data.models

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

/**
 * Authentication data models
 * One-to-one translation from iOS Swift models to Kotlin
 */

@Serializable
data class AuthenticationRequest(
    @SerialName("api_key")
    val apiKey: String,
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("sdk_version")
    val sdkVersion: String,
    val platform: String
)

@Serializable
data class AuthenticationResponse(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String,
    @SerialName("expires_in")
    val expiresIn: Long, // seconds
    @SerialName("token_type")
    val tokenType: String = "Bearer"
)

@Serializable
data class HealthCheckResponse(
    val status: String,
    val version: String,
    val timestamp: Long,
    val services: Map<String, String> = emptyMap()
)

/**
 * Stored token data for keychain
 */
data class StoredTokens(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Instant
)

/**
 * SDK Error extensions matching iOS pattern
 */
// Localized error description matching iOS pattern
val SDKError.errorDescription: String
    get() = message ?: "Unknown error"

val SDKError.recoverySuggestion: String
    get() = when (this) {
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
