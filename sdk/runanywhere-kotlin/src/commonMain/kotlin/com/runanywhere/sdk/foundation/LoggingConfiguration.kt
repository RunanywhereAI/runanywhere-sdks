package com.runanywhere.sdk.foundation

/**
 * Logging configuration for the SDK.
 * EXACT copy of iOS LoggingConfiguration struct.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/Models/Configuration/LoggingConfiguration.swift
 */
data class LoggingConfiguration(
    /** Enable local logging (console/file) */
    val enableLocalLogging: Boolean = true,
    /** Minimum log level filter */
    val minLogLevel: LogLevel = LogLevel.INFO,
    /** Include device metadata in logs */
    val includeDeviceMetadata: Boolean = true,
    /** Enable Sentry logging for crash reporting and error tracking.
     * When enabled, logs at warning level and above are sent to Sentry.
     * Default: true in development, false otherwise */
    val enableSentryLogging: Boolean = false,
) {
    /**
     * Validate the configuration.
     * @throws IllegalArgumentException if configuration is invalid
     */
    fun validate() {
        // Currently all configurations are valid
        // Add validation rules here if needed in the future
    }

    companion object {
        /**
         * Configuration preset for development environment.
         * Sentry logging is enabled by default for development.
         */
        val development =
            LoggingConfiguration(
                enableLocalLogging = true,
                minLogLevel = LogLevel.DEBUG,
                includeDeviceMetadata = false,
                enableSentryLogging = true,
            )

        /**
         * Configuration preset for staging environment.
         */
        val staging =
            LoggingConfiguration(
                enableLocalLogging = true,
                minLogLevel = LogLevel.INFO,
                includeDeviceMetadata = true,
                enableSentryLogging = false,
            )

        /**
         * Configuration preset for production environment.
         */
        val production =
            LoggingConfiguration(
                enableLocalLogging = false,
                minLogLevel = LogLevel.WARNING,
                includeDeviceMetadata = true,
                enableSentryLogging = false,
            )
    }

    /**
     * Builder pattern for LoggingConfiguration (matches iOS builder pattern).
     */
    class Builder {
        private var enableLocalLogging: Boolean = true
        private var minLogLevel: LogLevel = LogLevel.INFO
        private var includeDeviceMetadata: Boolean = true
        private var enableSentryLogging: Boolean = false

        fun enableLocalLogging(enabled: Boolean) = apply { this.enableLocalLogging = enabled }

        fun minLogLevel(level: LogLevel) = apply { this.minLogLevel = level }

        fun includeDeviceMetadata(include: Boolean) = apply { this.includeDeviceMetadata = include }

        fun enableSentryLogging(enabled: Boolean) = apply { this.enableSentryLogging = enabled }

        fun build() =
            LoggingConfiguration(
                enableLocalLogging = enableLocalLogging,
                minLogLevel = minLogLevel,
                includeDeviceMetadata = includeDeviceMetadata,
                enableSentryLogging = enableSentryLogging,
            )
    }
}

/**
 * Extension to create a builder for LoggingConfiguration.
 */
fun loggingConfiguration(block: LoggingConfiguration.Builder.() -> Unit): LoggingConfiguration =
    LoggingConfiguration.Builder().apply(block).build()
