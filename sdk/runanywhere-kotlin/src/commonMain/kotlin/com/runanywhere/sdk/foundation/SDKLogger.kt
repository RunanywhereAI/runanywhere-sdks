package com.runanywhere.sdk.foundation

/**
 * Log levels for SDK logging
 */
enum class LogLevel(val value: Int) {
    DEBUG(0),
    INFO(1),
    WARNING(2),
    ERROR(3)
}

/**
 * Platform-specific logger interface
 */
expect class PlatformLogger(tag: String) {
    fun debug(message: String)
    fun info(message: String)
    fun warning(message: String)
    fun error(message: String, throwable: Throwable? = null)
}

/**
 * SDK Logger for consistent logging across the SDK
 */
class SDKLogger(private val tag: String) {

    private val platformLogger = PlatformLogger(tag)

    companion object {
        private var currentLevel: LogLevel = LogLevel.INFO

        fun setLevel(level: LogLevel) {
            currentLevel = level
        }

        fun setLogLevel(level: com.runanywhere.sdk.data.models.LogLevel) {
            currentLevel = when(level) {
                com.runanywhere.sdk.data.models.LogLevel.DEBUG -> LogLevel.DEBUG
                com.runanywhere.sdk.data.models.LogLevel.INFO -> LogLevel.INFO
                com.runanywhere.sdk.data.models.LogLevel.WARNING -> LogLevel.WARNING
                com.runanywhere.sdk.data.models.LogLevel.ERROR -> LogLevel.ERROR
                com.runanywhere.sdk.data.models.LogLevel.NONE -> LogLevel.ERROR
            }
        }
    }

    fun debug(message: String) {
        if (currentLevel <= LogLevel.DEBUG) {
            platformLogger.debug(message)
        }
    }

    fun info(message: String) {
        if (currentLevel <= LogLevel.INFO) {
            platformLogger.info(message)
        }
    }

    fun warn(message: String) {
        if (currentLevel <= LogLevel.WARNING) {
            platformLogger.warning(message)
        }
    }

    fun warning(message: String) {
        warn(message)
    }

    fun error(message: String, throwable: Throwable? = null) {
        if (currentLevel <= LogLevel.ERROR) {
            platformLogger.error(message, throwable)
        }
    }
}
