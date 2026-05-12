/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for logging configuration.
 *
 * Mirrors Swift RunAnywhere+Logging.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.LogDestination
import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.infrastructure.logging.LoggingConfiguration
import com.runanywhere.sdk.public.RunAnywhere

// MARK: - Log Level

/**
 * Log level for SDK logging.
 */
enum class LogLevel(
    val value: Int,
) {
    /** No logging */
    NONE(0),

    /** Error level logging */
    ERROR(1),

    /** Warning level logging */
    WARNING(2),

    /** Info level logging */
    INFO(3),

    /** Debug level logging */
    DEBUG(4),

    /** Verbose level logging (all messages) */
    VERBOSE(5),
}

// MARK: - Logging Configuration

/**
 * Configure logging with a predefined configuration.
 *
 * @param config The logging configuration to apply
 */
fun RunAnywhere.configureLogging(config: LoggingConfiguration) {
    Logging.configure(config)
}

/**
 * Enable or disable local console logging.
 *
 * @param enabled Whether to enable local logging
 */
fun RunAnywhere.setLocalLoggingEnabled(enabled: Boolean) {
    Logging.setLocalLoggingEnabled(enabled)
}

/**
 * Set the SDK log level.
 *
 * @param level Log level to set
 */
fun RunAnywhere.setLogLevel(level: LogLevel) {
    // Delegate to CppBridge for actual implementation
    setLogLevelInternal(level)
}

/**
 * Enable or disable Sentry error tracking.
 *
 * @param enabled Whether to enable Sentry logging
 */
fun RunAnywhere.setSentryLoggingEnabled(enabled: Boolean) {
    Logging.setSentryLoggingEnabled(enabled)
}

/**
 * Add a custom log destination.
 *
 * @param destination The destination to add
 */
fun RunAnywhere.addLogDestination(destination: LogDestination) {
    Logging.addDestinationSync(destination)
}

// MARK: - Debugging Helpers

/**
 * Enable verbose debugging mode.
 *
 * @param enabled Whether to enable verbose mode
 */
fun RunAnywhere.setDebugMode(enabled: Boolean) {
    setLogLevel(if (enabled) LogLevel.DEBUG else LogLevel.INFO)
    setLocalLoggingEnabled(enabled)
}

/**
 * Internal function to set log level via CppBridge.
 */
internal expect fun RunAnywhere.setLogLevelInternal(level: LogLevel)

/**
 * Force flush all pending logs to destinations.
 */
expect fun RunAnywhere.flushLogs()
