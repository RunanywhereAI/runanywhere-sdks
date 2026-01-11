/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Log destination that sends logs to Sentry for error tracking.
 * Matches iOS SDK's SentryDestination.swift.
 */

package com.runanywhere.sdk.foundation.logging

import com.runanywhere.sdk.foundation.LogDestination
import com.runanywhere.sdk.foundation.LogEntry
import com.runanywhere.sdk.foundation.LogLevel
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
    private val minSentryLevel: LogLevel = LogLevel.WARNING

    // =============================================================================
    // LOG DESTINATION OPERATIONS
    // =============================================================================

    /**
     * Write a log entry to Sentry.
     *
     * @param entry The log entry to write
     */
    override fun write(entry: LogEntry) {
        if (!isAvailable || entry.level < minSentryLevel) {
            return
        }

        // Add as breadcrumb for context trail
        addBreadcrumb(entry)

        // For error and fault levels, capture as Sentry event
        if (entry.level >= LogLevel.ERROR) {
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

    // =============================================================================
    // PRIVATE HELPERS
    // =============================================================================

    /**
     * Add a breadcrumb for context trail.
     */
    private fun addBreadcrumb(entry: LogEntry) {
        val timestamp = Date(entry.timestamp.toEpochMilliseconds())
        val breadcrumb =
            Breadcrumb(timestamp).apply {
                category = entry.category
                message = entry.message
                level = convertToSentryLevel(entry.level)
                entry.metadata?.forEach { (key, value) ->
                    setData(key, value)
                }
            }

        Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Capture an error event in Sentry.
     */
    private fun captureEvent(entry: LogEntry) {
        val timestamp = Date(entry.timestamp.toEpochMilliseconds())
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
                entry.metadata?.forEach { (key, value) ->
                    setExtra(key, value)
                }

                // Add model info if present
                entry.modelId?.let { setExtra("model_id", it) }
                entry.framework?.let { setExtra("framework", it) }
                entry.errorCode?.let { setExtra("error_code", it) }

                // Add source location if present
                entry.file?.let { setExtra("source_file", it) }
                entry.line?.let { setExtra("source_line", it) }
                entry.function?.let { setExtra("source_function", it) }
            }

        Sentry.captureEvent(event)
    }

    /**
     * Convert SDK LogLevel to Sentry level.
     */
    private fun convertToSentryLevel(level: LogLevel): SentryLevel {
        return when (level) {
            LogLevel.TRACE -> SentryLevel.DEBUG
            LogLevel.DEBUG -> SentryLevel.DEBUG
            LogLevel.INFO -> SentryLevel.INFO
            LogLevel.WARNING -> SentryLevel.WARNING
            LogLevel.ERROR -> SentryLevel.ERROR
            LogLevel.FAULT -> SentryLevel.FATAL
        }
    }
}
