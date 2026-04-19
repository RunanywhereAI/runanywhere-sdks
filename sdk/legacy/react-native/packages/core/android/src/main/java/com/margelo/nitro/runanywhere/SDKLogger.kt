/**
 * SDKLogger.kt
 *
 * Android native logging implementation for React Native SDK.
 * Provides structured logging with category-based filtering.
 * Supports forwarding logs to TypeScript for centralized logging.
 *
 * Matches:
 * - iOS SDK: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 * - TypeScript: packages/core/src/Foundation/Logging/Logger/SDKLogger.ts
 * - iOS RN: packages/core/ios/SDKLogger.swift
 *
 * Usage:
 *   SDKLogger.shared.info("SDK initialized")
 *   SDKLogger.download.debug("Starting download: $url")
 *   SDKLogger.llm.error("Generation failed", mapOf("modelId" to "llama-3.2"))
 */

package com.margelo.nitro.runanywhere

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Log severity levels matching TypeScript LogLevel enum
 */
enum class LogLevel(val value: Int) {
    Debug(0),
    Info(1),
    Warning(2),
    Error(3),
    Fault(4);

    val description: String
        get() = when (this) {
            Debug -> "DEBUG"
            Info -> "INFO"
            Warning -> "WARN"
            Error -> "ERROR"
            Fault -> "FAULT"
        }

    companion object {
        fun fromValue(value: Int): LogLevel = entries.find { it.value == value } ?: Info
    }
}

/**
 * Log entry for forwarding to TypeScript
 * Matches TypeScript: LogEntry interface
 */
data class NativeLogEntry(
    val level: Int,
    val category: String,
    val message: String,
    val metadata: Map<String, Any?>?,
    val timestamp: Date
) {
    /**
     * Convert to Map for JSON serialization
     */
    fun toMap(): Map<String, Any?> {
        val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        return mapOf(
            "level" to level,
            "category" to category,
            "message" to message,
            "timestamp" to isoFormatter.format(timestamp),
            "metadata" to metadata?.mapValues { (_, value) ->
                when (value) {
                    is String, is Number, is Boolean -> value
                    else -> value?.toString()
                }
            }
        )
    }
}

/**
 * Interface for forwarding logs to TypeScript
 */
interface NativeLogForwarder {
    fun forwardLog(entry: NativeLogEntry)
}

/**
 * Simple logger for SDK components with category-based filtering.
 * Thread-safe and easy to use.
 *
 * Matches iOS: SDKLogger class
 */
class SDKLogger(
    /** Logger category (e.g., "LLM", "Download", "Models") */
    val category: String = "SDK"
) {
    companion object {
        /** Minimum log level (logs below this level are ignored) */
        @Volatile
        private var minLogLevel: LogLevel = LogLevel.Debug

        /** Whether local logcat logging is enabled */
        @Volatile
        private var localLoggingEnabled = true

        /** Whether to forward logs to TypeScript */
        @Volatile
        private var forwardingEnabled = true

        /** Log forwarder for TypeScript bridge */
        @Volatile
        private var logForwarder: NativeLogForwarder? = null

        // ==================================================================
        // Configuration
        // ==================================================================

        /**
         * Set the minimum log level.
         * @param level Minimum level to log
         */
        @JvmStatic
        fun setMinLogLevel(level: LogLevel) {
            minLogLevel = level
        }

        /**
         * Get the current minimum log level.
         */
        @JvmStatic
        fun getMinLogLevel(): LogLevel = minLogLevel

        /**
         * Enable or disable local logcat logging.
         * @param enabled Whether to log to logcat
         */
        @JvmStatic
        fun setLocalLoggingEnabled(enabled: Boolean) {
            localLoggingEnabled = enabled
        }

        /**
         * Enable or disable log forwarding to TypeScript.
         * @param enabled Whether to forward logs
         */
        @JvmStatic
        fun setForwardingEnabled(enabled: Boolean) {
            forwardingEnabled = enabled
        }

        /**
         * Set the log forwarder for TypeScript bridge.
         * @param forwarder Log forwarder implementation
         */
        @JvmStatic
        fun setLogForwarder(forwarder: NativeLogForwarder?) {
            logForwarder = forwarder
        }

        /**
         * Check if log forwarding is configured
         */
        @JvmStatic
        fun isForwardingConfigured(): Boolean = logForwarder != null && forwardingEnabled

        // ==================================================================
        // Convenience Loggers (Static)
        // ==================================================================

        /** Shared logger for general SDK operations. Category: "RunAnywhere" */
        @JvmField
        val shared = SDKLogger("RunAnywhere")

        /** Logger for LLM operations. Category: "LLM" */
        @JvmField
        val llm = SDKLogger("LLM")

        /** Logger for STT (Speech-to-Text) operations. Category: "STT" */
        @JvmField
        val stt = SDKLogger("STT")

        /** Logger for TTS (Text-to-Speech) operations. Category: "TTS" */
        @JvmField
        val tts = SDKLogger("TTS")

        /** Logger for download operations. Category: "Download" */
        @JvmField
        val download = SDKLogger("Download")

        /** Logger for model operations. Category: "Models" */
        @JvmField
        val models = SDKLogger("Models")

        /** Logger for core SDK operations. Category: "Core" */
        @JvmField
        val core = SDKLogger("Core")

        /** Logger for VAD operations. Category: "VAD" */
        @JvmField
        val vad = SDKLogger("VAD")

        /** Logger for network operations. Category: "Network" */
        @JvmField
        val network = SDKLogger("Network")

        /** Logger for events. Category: "Events" */
        @JvmField
        val events = SDKLogger("Events")

        /** Logger for archive/extraction operations. Category: "Archive" */
        @JvmField
        val archive = SDKLogger("Archive")

        /** Logger for audio decoding operations. Category: "AudioDecoder" */
        @JvmField
        val audioDecoder = SDKLogger("AudioDecoder")
    }

    // ==================================================================
    // Logging Methods
    // ==================================================================

    /**
     * Log a debug message.
     * @param message Log message
     * @param metadata Optional metadata map
     */
    @JvmOverloads
    fun debug(message: String, metadata: Map<String, Any?>? = null) {
        log(LogLevel.Debug, message, metadata)
    }

    /**
     * Log an info message.
     * @param message Log message
     * @param metadata Optional metadata map
     */
    @JvmOverloads
    fun info(message: String, metadata: Map<String, Any?>? = null) {
        log(LogLevel.Info, message, metadata)
    }

    /**
     * Log a warning message.
     * @param message Log message
     * @param metadata Optional metadata map
     */
    @JvmOverloads
    fun warning(message: String, metadata: Map<String, Any?>? = null) {
        log(LogLevel.Warning, message, metadata)
    }

    /**
     * Log an error message.
     * @param message Log message
     * @param metadata Optional metadata map
     */
    @JvmOverloads
    fun error(message: String, metadata: Map<String, Any?>? = null) {
        log(LogLevel.Error, message, metadata)
    }

    /**
     * Log a fault/critical message.
     * @param message Log message
     * @param metadata Optional metadata map
     */
    @JvmOverloads
    fun fault(message: String, metadata: Map<String, Any?>? = null) {
        log(LogLevel.Fault, message, metadata)
    }

    // ==================================================================
    // Error Logging
    // ==================================================================

    /**
     * Log a Throwable with full context.
     * @param throwable Throwable to log
     * @param additionalInfo Optional additional context
     */
    @JvmOverloads
    fun logError(throwable: Throwable, additionalInfo: String? = null) {
        var message = throwable.message ?: throwable.toString()
        if (additionalInfo != null) {
            message += " | Context: $additionalInfo"
        }

        val metadata = mutableMapOf<String, Any?>(
            "error_class" to throwable.javaClass.simpleName,
            "error_message" to throwable.message
        )

        throwable.cause?.let { cause ->
            metadata["error_cause"] = cause.message
        }

        log(LogLevel.Error, message, metadata)

        // Also log stack trace at debug level
        if (minLogLevel <= LogLevel.Debug) {
            Log.d(category, "Stack trace:", throwable)
        }
    }

    // ==================================================================
    // Core Logging
    // ==================================================================

    /**
     * Log a message with the specified level.
     * @param level Log level
     * @param message Log message
     * @param metadata Optional metadata map
     */
    fun log(level: LogLevel, message: String, metadata: Map<String, Any?>? = null) {
        if (level.value < minLogLevel.value) return

        val timestamp = Date()

        // Build formatted message
        var output = "[$category] $message"
        if (!metadata.isNullOrEmpty()) {
            val metaStr = metadata.entries.joinToString(", ") { "${it.key}=${it.value}" }
            output += " | $metaStr"
        }

        // Log to Android Log (logcat) if enabled
        if (localLoggingEnabled) {
            when (level) {
                LogLevel.Debug -> Log.d(category, output)
                LogLevel.Info -> Log.i(category, output)
                LogLevel.Warning -> Log.w(category, output)
                LogLevel.Error -> Log.e(category, output)
                LogLevel.Fault -> Log.wtf(category, output) // "What a Terrible Failure"
            }
        }

        // Forward to TypeScript if enabled
        if (forwardingEnabled) {
            logForwarder?.forwardLog(
                NativeLogEntry(
                    level = level.value,
                    category = category,
                    message = message,
                    metadata = metadata,
                    timestamp = timestamp
                )
            )
        }
    }
}
