/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for logging configuration.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere

// Internal log level state
@Volatile
private var currentLogLevel: LogLevel = LogLevel.INFO

private val logger = SDKLogger.shared

internal actual fun RunAnywhere.setLogLevelInternal(level: LogLevel) {
    currentLogLevel = level
    logger.debug("Log level set to ${level.name}")
}

actual fun RunAnywhere.flushLogs() {
    // Logs are written immediately via platform adapter, no buffering
    logger.debug("Logs flushed")
}
