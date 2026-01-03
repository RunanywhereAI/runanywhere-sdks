/*
 * Copyright 2024 RunAnywhere SDK
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
    // The platform adapter uses its own log level constants
    // Map our LogLevel to the platform adapter's level
    val platformLevel = when (level) {
        LogLevel.VERBOSE -> CppBridgePlatformAdapter.LogLevel.TRACE
        LogLevel.DEBUG -> CppBridgePlatformAdapter.LogLevel.DEBUG
        LogLevel.INFO -> CppBridgePlatformAdapter.LogLevel.INFO
        LogLevel.WARNING -> CppBridgePlatformAdapter.LogLevel.WARN
        LogLevel.ERROR -> CppBridgePlatformAdapter.LogLevel.ERROR
        LogLevel.NONE -> CppBridgePlatformAdapter.LogLevel.FATAL // Use FATAL as "no logging"
    }
    // Store for later use - actual configuration happens via platform adapter
    CppBridgePlatformAdapter.logCallback(
        CppBridgePlatformAdapter.LogLevel.DEBUG,
        "RunAnywhere",
        "Log level set to ${level.name}"
    )
}

actual fun RunAnywhere.setFileLogging(enabled: Boolean, path: String?) {
    fileLoggingEnabled = enabled
    fileLoggingPath = path
    CppBridgePlatformAdapter.logCallback(
        CppBridgePlatformAdapter.LogLevel.DEBUG,
        "RunAnywhere",
        "File logging ${if (enabled) "enabled" else "disabled"}${path?.let { " at $it" } ?: ""}"
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
        "Logs flushed"
    )
}
