/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for logging configuration.
 *
 * Mirrors Swift RunAnywhere+Logging.swift pattern (7-method surface).
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
 * Mirrors Swift `RunAnywhere.configureLogging(_:)`.
 */
fun RunAnywhere.configureLogging(config: LoggingConfiguration) {
    Logging.configure(config)
}

/**
 * Enable or disable local console logging.
 * Mirrors Swift `RunAnywhere.setLocalLoggingEnabled(_:)`.
 */
fun RunAnywhere.setLocalLoggingEnabled(enabled: Boolean) {
    Logging.setLocalLoggingEnabled(enabled)
}

/**
 * Set the minimum log level captured by the SDK logger.
 * Mirrors Swift `RunAnywhere.setLogLevel(_:)`.
 */
fun RunAnywhere.setLogLevel(level: LogLevel) {
    Logging.setMinLogLevel(level)
}

/**
 * Enable or disable Sentry error tracking.
 * Mirrors Swift `RunAnywhere.setSentryLoggingEnabled(_:)`.
 */
fun RunAnywhere.setSentryLoggingEnabled(enabled: Boolean) {
    Logging.setSentryLoggingEnabled(enabled)
}

/**
 * Add a custom [LogDestination] to the SDK logger.
 * Mirrors Swift `RunAnywhere.addLogDestination(_:)`.
 */
fun RunAnywhere.addLogDestination(destination: LogDestination) {
    Logging.addDestinationSync(destination)
}

// MARK: - Debugging Helpers

/**
 * Enable verbose debugging mode: sets min level to DEBUG and turns on local
 * console logging (or sets min level to INFO and disables local logging when
 * `enabled = false`). Mirrors Swift `RunAnywhere.setDebugMode(_:)`.
 */
fun RunAnywhere.setDebugMode(enabled: Boolean) {
    setLogLevel(if (enabled) LogLevel.DEBUG else LogLevel.INFO)
    setLocalLoggingEnabled(enabled)
}

/**
 * Force flush all pending logs to every registered destination.
 * Mirrors Swift `RunAnywhere.flushLogs()`.
 */
fun RunAnywhere.flushLogs() {
    Logging.flush()
}
