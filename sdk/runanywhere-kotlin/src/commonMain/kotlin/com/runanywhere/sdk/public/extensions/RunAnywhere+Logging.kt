/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for logging configuration.
 *
 * Mirrors Swift RunAnywhere+Logging.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

// MARK: - Log Level

/**
 * Log level for SDK logging.
 */
enum class LogLevel(val value: Int) {
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
    VERBOSE(5)
}

// MARK: - Logging Configuration

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
 * Internal function to set log level via CppBridge.
 */
internal expect fun RunAnywhere.setLogLevelInternal(level: LogLevel)

/**
 * Enable or disable file logging.
 *
 * @param enabled Whether to enable file logging
 * @param path Optional path for log file
 */
expect fun RunAnywhere.setFileLogging(enabled: Boolean, path: String? = null)

/**
 * Get the current log level.
 *
 * @return Current log level
 */
expect fun RunAnywhere.getLogLevel(): LogLevel

/**
 * Flush pending log messages.
 */
expect fun RunAnywhere.flushLogs()
