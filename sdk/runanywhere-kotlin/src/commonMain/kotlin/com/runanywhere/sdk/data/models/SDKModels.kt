package com.runanywhere.sdk.data.models

import com.runanywhere.sdk.models.ModelInfo

/**
 * Extensions for SDKEnvironment
 */
val SDKEnvironment.defaultLogLevel: LogLevel
    get() = when (this) {
        SDKEnvironment.DEVELOPMENT -> LogLevel.DEBUG
        SDKEnvironment.STAGING -> LogLevel.INFO
        SDKEnvironment.PRODUCTION -> LogLevel.WARNING
    }

val SDKEnvironment.defaultBaseURL: String
    get() = when (this) {
        SDKEnvironment.DEVELOPMENT -> "http://localhost:8080"
        SDKEnvironment.STAGING -> "https://staging-api.runanywhere.ai"
        SDKEnvironment.PRODUCTION -> "https://api.runanywhere.ai"
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
