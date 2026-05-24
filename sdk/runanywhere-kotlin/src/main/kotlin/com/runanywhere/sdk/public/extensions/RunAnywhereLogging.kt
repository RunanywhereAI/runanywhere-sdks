/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for logging configuration.
 *
 * Mirrors Swift RunAnywhere+Logging.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.Logging
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

// MARK: - Debugging Helpers

internal fun RunAnywhere.setLogLevelInternal(level: LogLevel) {
    Logging.setMinLogLevel(level)
}

fun RunAnywhere.flushLogs() {
    Logging.flush()
}
