package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.events.SDKLoggingEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Logging & Debugging extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+Logging.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Logging/RunAnywhere+Logging.swift
 *
 * Note: Phase 2 implementation with placeholders - these APIs provide the structure
 * but some functionality requires additional logging infrastructure to be implemented.
 */

private val loggingLogger = SDKLogger("LoggingAPI")

/**
 * Configure SDK-wide logging settings
 * Matches iOS configureSDKLogging() method
 *
 * @param level Minimum log level (use SDKLogger.LogLevel.DEBUG, INFO, WARNING, or ERROR)
 * @param enableConsoleOutput Whether to output logs to console (placeholder)
 */
fun RunAnywhereSDK.configureSDKLogging(
    level: String,
    enableConsoleOutput: Boolean = true
) {
    loggingLogger.debug("Configuring SDK logging: level=$level, console=$enableConsoleOutput")

    // Publish event
    events.publish(SDKLoggingEvent.ConfigurationUpdated(
        level = level,
        consoleEnabled = enableConsoleOutput
    ))

    // Set log level based on string
    val logLevel = when (level.uppercase()) {
        "DEBUG" -> SDKLogger.Companion.LogLevel.DEBUG
        "INFO" -> SDKLogger.Companion.LogLevel.INFO
        "WARNING" -> SDKLogger.Companion.LogLevel.WARNING
        "ERROR" -> SDKLogger.Companion.LogLevel.ERROR
        else -> SDKLogger.Companion.LogLevel.INFO
    }
    SDKLogger.setLogLevel(logLevel)

    loggingLogger.info("SDK logging configured: level=$level")
}

/**
 * Configure local logging settings (file-based)
 * Matches iOS configureLocalLogging() method
 *
 * @param enabled Whether to enable local file logging
 * @param maxFileSizeMB Maximum log file size in MB
 * @param maxFileCount Maximum number of log files to keep
 */
suspend fun RunAnywhereSDK.configureLocalLogging(
    enabled: Boolean,
    maxFileSizeMB: Int = 10,
    maxFileCount: Int = 5
) {
    loggingLogger.debug("Configuring local logging: enabled=$enabled, maxSize=${maxFileSizeMB}MB, maxFiles=$maxFileCount")

    // Publish event
    events.publish(SDKLoggingEvent.LocalLoggingConfigured(
        enabled = enabled,
        maxSizeMB = maxFileSizeMB,
        maxFileCount = maxFileCount
    ))

    // TODO: Implement file logging when file logging service is available
    loggingLogger.warning("Local file logging configuration is a placeholder - not yet implemented")

    loggingLogger.info("Local logging configuration saved (placeholder): enabled=$enabled")
}

/**
 * Set log level for specific component
 * Matches iOS setLogLevel() method
 *
 * @param componentName Name of the component (e.g., "STT", "LLM", "VAD")
 * @param level Log level (DEBUG, INFO, WARNING, ERROR)
 */
fun RunAnywhereSDK.setLogLevel(componentName: String, level: String) {
    loggingLogger.debug("Setting log level for component '$componentName': $level")

    // Publish event
    events.publish(SDKLoggingEvent.ComponentLogLevelChanged(
        component = componentName,
        level = level
    ))

    // TODO: Implement component-specific log level when per-component logging is available
    loggingLogger.warning("Component-specific log levels are not yet implemented - using global level")

    loggingLogger.info("Log level change requested for '$componentName': $level")
}

/**
 * Enable or disable debug mode
 * Matches iOS setDebugMode() method
 *
 * @param enabled Whether to enable debug mode
 */
fun RunAnywhereSDK.setDebugMode(enabled: Boolean) {
    loggingLogger.debug("Setting debug mode: $enabled")

    // Publish event
    events.publish(SDKLoggingEvent.DebugModeChanged(enabled))

    // Set log level to DEBUG if enabled, otherwise INFO
    SDKLogger.setLogLevel(if (enabled) SDKLogger.Companion.LogLevel.DEBUG else SDKLogger.Companion.LogLevel.INFO)

    loggingLogger.info("Debug mode ${if (enabled) "enabled" else "disabled"}")
}

/**
 * Flush all pending log entries
 * Matches iOS flushAll() method
 */
suspend fun RunAnywhereSDK.flushAll() {
    loggingLogger.debug("Flushing all logs")

    // Publish event
    events.publish(SDKLoggingEvent.FlushStarted)

    try {
        // TODO: Implement log flushing when file logging is available
        // For now, this is a no-op since we only have console logging
        loggingLogger.warning("Log flushing is a placeholder - no buffered logs to flush")

        // Publish success event
        events.publish(SDKLoggingEvent.FlushCompleted)

        loggingLogger.info("Flush completed (no-op for console logging)")
    } catch (e: Exception) {
        loggingLogger.error("Failed to flush logs: ${e.message}")
        events.publish(SDKLoggingEvent.FlushFailed(e.message ?: "Unknown error"))
        throw e
    }
}
