package com.runanywhere.sdk.data.models

/**
 * SDK Environment modes
 */
enum class SDKEnvironment {
    DEVELOPMENT,  // Use mock services, no API calls
    STAGING,
    PRODUCTION;

    val defaultLogLevel: LogLevel
        get() = when (this) {
            DEVELOPMENT -> LogLevel.DEBUG
            STAGING -> LogLevel.INFO
            PRODUCTION -> LogLevel.WARNING
        }

    val defaultBaseURL: String
        get() = when (this) {
            DEVELOPMENT -> "http://localhost:8080"
            STAGING -> "https://staging-api.runanywhere.ai"
            PRODUCTION -> "https://api.runanywhere.ai"
        }
}

/**
 * SDK initialization parameters
 */
data class SDKInitParams(
    val apiKey: String,
    val baseURL: String?,
    val environment: SDKEnvironment
)

/**
 * Configuration data for the SDK
 */
data class ConfigurationData(
    val id: String,
    val apiKey: String,
    val source: ConfigurationSource
) {
    companion object {
        fun default(): ConfigurationData {
            return ConfigurationData(
                id = "default-config",
                apiKey = "",
                source = ConfigurationSource.LOCAL
            )
        }
    }
}

/**
 * Configuration source
 */
enum class ConfigurationSource {
    LOCAL,
    REMOTE
}

/**
 * Model information
 */
data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val downloadURL: String?,
    val downloadSize: Long,
    val memoryRequired: Long,
    val contextLength: Int = 0,
    val supportsThinking: Boolean = false,
    val localPath: String? = null
)

/**
 * Model categories
 */
enum class ModelCategory {
    SPEECH_RECOGNITION,
    LANGUAGE,
    VISION,
    EMBEDDING,
    OTHER
}

/**
 * Model formats
 */
enum class ModelFormat {
    GGML,
    GGUF,
    ONNX,
    TENSORFLOW,
    COREML,
    OTHER
}

/**
 * Loaded model information
 */
data class LoadedModel(
    val model: ModelInfo,
    val localPath: String,
    val loadedAt: Long
)

/**
 * Log levels
 */
enum class LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    NONE
}

/**
 * Health status
 */
enum class HealthStatus {
    HEALTHY,
    DEGRADED,
    UNHEALTHY
}

/**
 * Authentication response
 */
data class AuthenticationResponse(
    val accessToken: String,
    val refreshToken: String,
    val expiresIn: Long,
    val tokenType: String
)

/**
 * Health check response
 */
data class HealthCheckResponse(
    val status: HealthStatus,
    val version: String,
    val timestamp: Long
)

/**
 * SDK Errors
 */
sealed class SDKError : Exception() {
    object NotInitialized : SDKError() {
        override val message = "SDK is not initialized. Call RunAnywhere.initialize() first."
    }

    data class InvalidAPIKey(override val message: String) : SDKError()

    data class ModelNotFound(val modelId: String) : SDKError() {
        override val message = "Model not found: $modelId"
    }

    data class LoadingFailed(override val message: String) : SDKError()

    data class TranscriptionFailed(override val message: String) : SDKError()
}
