/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Log destination that sends logs to Sentry for error tracking.
 * Matches iOS SDK's SentryDestination.swift.
 */

package com.runanywhere.sdk.infrastructure.logging

import ai.runanywhere.proto.v1.LogEntry
import ai.runanywhere.proto.v1.LogLevel
import io.sentry.Breadcrumb
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.protocol.Message
import java.util.Date

/**
 * Log destination that sends warning+ logs to Sentry.
 *
 * - Warning level: Added as breadcrumbs for context trail
 * - Error/Fault level: Captured as Sentry events
 */
class SentryDestination : LogDestination {
    companion object {
        const val DESTINATION_ID = "com.runanywhere.logging.sentry"
    }

    /**
     * Unique identifier for this destination.
     */
    override val identifier: String = DESTINATION_ID

    /**
     * Whether this destination is available for writing.
     */
    override val isAvailable: Boolean
        get() = SentryManager.isInitialized

    /**
     * Only send warning level and above to Sentry.
     */
    private val minSentryLevel: LogLevel = LogLevel.LOG_LEVEL_WARNING

    // Log destination operations

    /**
     * Write a log entry to Sentry.
     *
     * @param entry The log entry to write
     */
    override fun write(entry: LogEntry) {
        // proto LogLevel: larger value = more severe (TRACE=0, DEBUG=1,
        // INFO=2, WARNING=3, ERROR=4, FATAL=5). Send to Sentry iff entry
        // severity is at or above the min Sentry level.
        if (!isAvailable || entry.level.value < minSentryLevel.value) {
            return
        }

        // Add as breadcrumb for context trail
        addBreadcrumb(entry)

        // ERROR + FATAL capture as Sentry events; WARNING stays a breadcrumb.
        if (entry.level.value >= LogLevel.LOG_LEVEL_ERROR.value) {
            captureEvent(entry)
        }
    }

    /**
     * Flush any buffered entries.
     */
    override fun flush() {
        if (!isAvailable) return
        SentryManager.flush()
    }

    // Private helpers

    /**
     * Add a breadcrumb for context trail.
     */
    private fun addBreadcrumb(entry: LogEntry) {
        val timestamp = Date(entry.timestamp_unix_ms)
        val breadcrumb =
            Breadcrumb(timestamp).apply {
                category = entry.category
                message = entry.message
                level = convertToSentryLevel(entry.level)
                entry.metadata.forEach { (key, value) ->
                    setData(key, value)
                }
            }

        Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Capture an error event in Sentry.
     */
    private fun captureEvent(entry: LogEntry) {
        val timestamp = Date(entry.timestamp_unix_ms)
        val event =
            SentryEvent(timestamp).apply {
                level = convertToSentryLevel(entry.level)
                message =
                    Message().apply {
                        formatted = entry.message
                    }

                // Add tags
                setTag("category", entry.category)
                setTag("log_level", entry.level.toString())

                // Add metadata as extras
                entry.metadata.forEach { (key, value) ->
                    setExtra(key, value)
                }

                // Add model info if present (proto: "" / 0 means unset)
                entry.model_id.takeIf { it.isNotEmpty() }?.let { setExtra("model_id", it) }
                entry.framework.takeIf { it.isNotEmpty() }?.let { setExtra("framework", it) }
                entry.error_code.takeIf { it != 0 }?.let { setExtra("error_code", it) }

                // Add source location if present
                entry.file_.takeIf { it.isNotEmpty() }?.let { setExtra("source_file", it) }
                entry.line.takeIf { it != 0 }?.let { setExtra("source_line", it) }
                entry.function.takeIf { it.isNotEmpty() }?.let { setExtra("source_function", it) }
            }

        Sentry.captureEvent(event)
    }

    /**
     * Convert SDK LogLevel to Sentry level.
     */
    private fun convertToSentryLevel(level: LogLevel): SentryLevel {
        return when (level) {
            LogLevel.LOG_LEVEL_TRACE -> SentryLevel.DEBUG
            LogLevel.LOG_LEVEL_DEBUG -> SentryLevel.DEBUG
            LogLevel.LOG_LEVEL_INFO -> SentryLevel.INFO
            LogLevel.LOG_LEVEL_WARNING -> SentryLevel.WARNING
            LogLevel.LOG_LEVEL_ERROR -> SentryLevel.ERROR
            LogLevel.LOG_LEVEL_FATAL -> SentryLevel.FATAL
        }
    }
}
