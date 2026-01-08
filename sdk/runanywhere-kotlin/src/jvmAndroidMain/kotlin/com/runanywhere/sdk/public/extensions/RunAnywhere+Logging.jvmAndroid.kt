/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for logging configuration.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.public.RunAnywhere

// Internal log level state
@Volatile
private var currentLogLevel: LogLevel = LogLevel.INFO

// File logging state
@Volatile
private var fileLoggingEnabled: Boolean = false

@Volatile
private var fileLoggingPath: String? = null

internal actual fun RunAnywhere.setLogLevelInternal(level: LogLevel) {
    currentLogLevel = level
    // Log the level change (platform adapter uses its own log level constants)
    CppBridgePlatformAdapter.logCallback(
        CppBridgePlatformAdapter.LogLevel.DEBUG,
        "RunAnywhere",
        "Log level set to ${level.name}",
    )
}

actual fun RunAnywhere.setFileLogging(enabled: Boolean, path: String?) {
    fileLoggingEnabled = enabled
    fileLoggingPath = path
    CppBridgePlatformAdapter.logCallback(
        CppBridgePlatformAdapter.LogLevel.DEBUG,
        "RunAnywhere",
        "File logging ${if (enabled) "enabled" else "disabled"}${path?.let { " at $it" } ?: ""}",
    )
}

actual fun RunAnywhere.getLogLevel(): LogLevel {
    return currentLogLevel
}

actual fun RunAnywhere.flushLogs() {
    // Logs are written immediately via platform adapter, no buffering
    CppBridgePlatformAdapter.logCallback(
        CppBridgePlatformAdapter.LogLevel.DEBUG,
        "RunAnywhere",
        "Logs flushed",
    )
}
