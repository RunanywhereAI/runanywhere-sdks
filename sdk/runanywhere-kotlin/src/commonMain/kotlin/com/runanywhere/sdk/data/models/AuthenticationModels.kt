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
 * SDK Error types matching iOS exactly
 * Sealed class equivalent to Swift enum with associated values
 */
sealed class SDKError : Exception() {
    object NotInitialized : SDKError() {
        override val message: String = "SDK not initialized"
    }

    data class InvalidAPIKey(override val message: String) : SDKError()
    data class AuthenticationFailed(override val message: String) : SDKError()
    data class NetworkError(override val message: String) : SDKError()
    data class DatabaseInitializationFailed(override val cause: Throwable) : SDKError() {
        override val message: String = "Database initialization failed: ${cause.message}"
    }
    data class ConfigurationError(override val message: String) : SDKError()
    data class ModelNotFound(val modelId: String) : SDKError() {
        override val message: String = "Model not found: $modelId"
    }
    data class ModelLoadFailed(val modelId: String, override val cause: Throwable?) : SDKError() {
        override val message: String = "Failed to load model $modelId: ${cause?.message}"
    }
    data class GenerationFailed(override val message: String) : SDKError()
    data class ComponentError(val component: String, override val message: String) : SDKError()
    data class FileSystemError(override val message: String) : SDKError()
    data class PermissionDenied(override val message: String) : SDKError()

    // Localized error description matching iOS pattern
    val errorDescription: String
        get() = message

    val recoverySuggestion: String
        get() = when (this) {
            is NotInitialized -> "Call RunAnywhere.initialize() first"
            is InvalidAPIKey -> "Check your API key and ensure it's valid"
            is AuthenticationFailed -> "Verify your API key and network connection"
            is NetworkError -> "Check your internet connection and try again"
            is DatabaseInitializationFailed -> "Restart the app or clear app data"
            is ConfigurationError -> "Check your configuration parameters"
            is ModelNotFound -> "Ensure the model is available or download it first"
            is ModelLoadFailed -> "Check available memory and model file integrity"
            is GenerationFailed -> "Try adjusting generation parameters or check model status"
            is ComponentError -> "Check component configuration and dependencies"
            is FileSystemError -> "Check storage permissions and available space"
            is PermissionDenied -> "Grant required permissions in app settings"
        }
}
