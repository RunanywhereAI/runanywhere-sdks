package com.runanywhere.sdk.infrastructure.logging

import ai.runanywhere.proto.v1.LogEntry
import ai.runanywhere.proto.v1.LogLevel
import ai.runanywhere.proto.v1.LoggingConfiguration
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// LOG LEVEL / LOG ENTRY / LOGGING CONFIGURATION (proto-canonical)
//
// LogLevel, LogEntry and LoggingConfiguration are now the proto-generated
// types in ai.runanywhere.proto.v1. LogLevel values: LOG_LEVEL_TRACE(0),
// LOG_LEVEL_DEBUG(1), LOG_LEVEL_INFO(2), LOG_LEVEL_WARNING(3),
// LOG_LEVEL_ERROR(4), LOG_LEVEL_FATAL(5). Ordered by severity, larger value =
// more severe. Filtering: log iff `level.value >= minLogLevel.value`.
//
// LogEntry's extra Kotlin context (file/line/function/error_code/model_id/
// framework) maps onto the proto fields `file_`, `line`, `function`,
// `error_code`, `model_id`, `framework`; `timestamp_unix_ms` carries the
// epoch-millis timestamp. Proto fields use scalar defaults ("" / 0) instead of
// nullable — empty/zero means "unset".

// Per-environment LoggingConfiguration presets. The proto LoggingConfiguration
// is a flat message with no companion helpers, so the development/staging/
// production factories live here.

internal object LoggingConfigurationPresets {
    /** Development: debug logging + detailed source location. */
    val development =
        LoggingConfiguration(
            enable_local_logging = true,
            min_log_level = LogLevel.LOG_LEVEL_DEBUG,
            include_source_location = true,
            enable_remote_logging = false,
            enable_sentry_logging = false,
            include_device_metadata = true,
        )

    /** Staging: info level with source location for debugging. */
    val staging =
        LoggingConfiguration(
            enable_local_logging = true,
            min_log_level = LogLevel.LOG_LEVEL_INFO,
            include_source_location = true,
            enable_remote_logging = false,
            enable_sentry_logging = true,
            include_device_metadata = true,
        )

    /** Production: warning+ only, Sentry enabled for error tracking. */
    val production =
        LoggingConfiguration(
            enable_local_logging = false,
            min_log_level = LogLevel.LOG_LEVEL_WARNING,
            include_source_location = false,
            enable_remote_logging = false,
            enable_sentry_logging = true,
            include_device_metadata = true,
        )

    fun forEnvironment(environment: SDKEnvironment): LoggingConfiguration =
        when (environment) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> development
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> staging
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> production
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> development
        }
}

// Log destination protocol

/**
 * Protocol for log output destinations (Console, remote services, etc.).
 * Matches Swift SDK LogDestination protocol.
 */
interface LogDestination {
    /** Unique identifier for this destination */
    val identifier: String

    /** Whether this destination is available for writing */
    val isAvailable: Boolean

    /** Write a log entry to this destination */
    fun write(entry: LogEntry)

    /** Flush any buffered entries */
    fun flush()
}

// Logging (central service)

/**
 * Central logging service that routes logs to multiple destinations.
 * Thread-safe using Mutex for state management.
 * Matches Swift SDK Logging class.
 */
object Logging {
    private val mutex = Mutex()

    // Thread-safe state
    private var _configuration: LoggingConfiguration = LoggingConfigurationPresets.development
    private val _destinations: MutableList<LogDestination> = mutableListOf()

    // Bridge callback for forwarding logs to runanywhere-commons
    private var commonsLogBridge: ((LogEntry) -> Unit)? = null

    /**
     * Current logging configuration.
     */
    var configuration: LoggingConfiguration
        get() = _configuration
        set(value) {
            _configuration = value
        }

    /**
     * List of registered log destinations.
     */
    val destinations: List<LogDestination>
        get() = _destinations.toList()

    // Configuration

    /**
     * Configure the logging system.
     */
    fun configure(config: LoggingConfiguration) {
        _configuration = config
    }

    /**
     * Apply configuration based on SDK environment.
     */
    fun applyEnvironmentConfiguration(environment: SDKEnvironment) {
        configure(LoggingConfigurationPresets.forEnvironment(environment))
    }

    /**
     * Set whether local logging is enabled.
     */
    fun setLocalLoggingEnabled(enabled: Boolean) {
        _configuration = _configuration.copy(enable_local_logging = enabled)
    }

    /**
     * Set the minimum log level.
     */
    fun setMinLogLevel(level: LogLevel) {
        _configuration = _configuration.copy(min_log_level = level)
    }

    /**
     * Set whether to include source location in logs.
     */
    fun setIncludeSourceLocation(include: Boolean) {
        _configuration = _configuration.copy(include_source_location = include)
    }

    /**
     * Set whether to include device metadata in logs.
     */
    fun setIncludeDeviceMetadata(include: Boolean) {
        _configuration = _configuration.copy(include_device_metadata = include)
    }

    /**
     * Set whether Sentry logging is enabled.
     * When enabled, warning+ logs are sent to Sentry for error tracking.
     *
     * Note: Call setupSentry() after enabling to initialize the Sentry SDK.
     */
    fun setSentryLoggingEnabled(enabled: Boolean) {
        val oldConfig = _configuration
        _configuration = _configuration.copy(enable_sentry_logging = enabled)

        // Handle Sentry state changes via the platform-specific hook
        if (enabled && !oldConfig.enable_sentry_logging) {
            sentrySetupHook?.invoke()
        } else if (!enabled && oldConfig.enable_sentry_logging) {
            sentryTeardownHook?.invoke()
        }
    }

    /**
     * Hook for platform-specific Sentry setup.
     * Set by the platform layer (jvmAndroidMain) during initialization.
     */
    var sentrySetupHook: (() -> Unit)? = null
        internal set

    /**
     * Hook for platform-specific Sentry teardown.
     * Set by the platform layer (jvmAndroidMain) during shutdown.
     */
    var sentryTeardownHook: (() -> Unit)? = null
        internal set

    /**
     * Hook for delegating metadata redaction policy to the canonical C++
     * implementation `rac_log_metadata_should_redact`. Set by the platform
     * layer (jvmAndroidMain) once the native library is loaded, so Kotlin
     * and C++ logs share the same sensitive-substring list. When unset
     * (e.g. native library not yet loaded), `sanitizeMetadata` falls back
     * to the hardcoded `sensitivePatterns` list below.
     */
    var shouldRedactPolicy: ((String) -> Boolean)? = null
        internal set

    /**
     * Set the bridge callback for forwarding logs to runanywhere-commons.
     * This enables integration with the C/C++ logging system.
     */
    fun setCommonsLogBridge(bridge: ((LogEntry) -> Unit)?) {
        commonsLogBridge = bridge
    }

    // Core logging

    /**
     * Log a message with optional metadata.
     */
    fun log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: Map<String, Any?>? = null,
        file: String? = null,
        line: Int? = null,
        function: String? = null,
        errorCode: Int? = null,
        modelId: String? = null,
        framework: String? = null,
    ) {
        val config = _configuration

        // Check if level meets minimum threshold. proto LogLevel severity:
        // LOG_LEVEL_TRACE(0) = least severe, LOG_LEVEL_FATAL(5) = most severe.
        // A log is emitted iff its severity is at least the configured
        // threshold (mirrors Swift `level >= config.minLogLevel`).
        if (level.value < config.min_log_level.value) return

        // Check if any logging is enabled
        if (!config.enable_local_logging && !config.enable_remote_logging && _destinations.isEmpty()) return

        // Create log entry. Proto LogEntry uses scalar defaults ("" / 0) for
        // unset fields rather than nullables.
        val includeSource = config.include_source_location
        val entry =
            LogEntry(
                timestamp_unix_ms = getCurrentTimeMillis(),
                level = level,
                category = category,
                message = message,
                metadata = sanitizeMetadata(metadata) ?: emptyMap(),
                file_ = if (includeSource) file.orEmpty() else "",
                line = if (includeSource) (line ?: 0) else 0,
                function = if (includeSource) function.orEmpty() else "",
                error_code = errorCode ?: 0,
                model_id = modelId.orEmpty(),
                framework = framework.orEmpty(),
            )

        // Write to console if local logging enabled
        if (config.enable_local_logging) {
            printToConsole(entry)
        }

        // Forward to runanywhere-commons bridge if set
        commonsLogBridge?.invoke(entry)

        // Write to all registered destinations (snapshot to avoid concurrent modification)
        for (destination in _destinations.toList()) {
            if (destination.isAvailable) {
                destination.write(entry)
            }
        }
    }

    // Destination management

    /**
     * Add a log destination.
     */
    suspend fun addDestination(destination: LogDestination) {
        mutex.withLock {
            if (_destinations.none { it.identifier == destination.identifier }) {
                _destinations.add(destination)
            }
        }
    }

    /**
     * Add a log destination (non-suspending version).
     */
    @Synchronized
    fun addDestinationSync(destination: LogDestination) {
        if (_destinations.none { it.identifier == destination.identifier }) {
            _destinations.add(destination)
        }
    }

    /**
     * Remove a log destination.
     */
    suspend fun removeDestination(destination: LogDestination) {
        mutex.withLock {
            _destinations.removeAll { it.identifier == destination.identifier }
        }
    }

    /**
     * Remove a log destination (non-suspending version).
     */
    fun removeDestinationSync(destination: LogDestination) {
        _destinations.removeAll { it.identifier == destination.identifier }
    }

    /**
     * Flush all destinations.
     */
    fun flush() {
        for (destination in _destinations) {
            destination.flush()
        }
    }

    // Private helpers

    private fun printToConsole(entry: LogEntry) {
        val levelIndicator =
            when (entry.level) {
                LogLevel.LOG_LEVEL_TRACE -> "[TRACE]"
                LogLevel.LOG_LEVEL_DEBUG -> "[DEBUG]"
                LogLevel.LOG_LEVEL_INFO -> "[INFO]"
                LogLevel.LOG_LEVEL_WARNING -> "[WARN]"
                LogLevel.LOG_LEVEL_ERROR -> "[ERROR]"
                LogLevel.LOG_LEVEL_FATAL -> "[FATAL]"
            }

        val output =
            buildString {
                append(levelIndicator)
                append(" [")
                append(entry.category)
                append("] ")
                append(entry.message)

                // Add metadata if present
                entry.metadata.takeIf { it.isNotEmpty() }?.let { meta ->
                    append(" | ")
                    append(meta.entries.joinToString(", ") { "${it.key}=${it.value}" })
                }

                // Add source location if present (proto: "" / 0 means unset)
                if (entry.file_.isNotEmpty() || entry.function.isNotEmpty()) {
                    append(" @ ")
                    if (entry.file_.isNotEmpty()) append(entry.file_)
                    if (entry.line != 0) append(":${entry.line}")
                    if (entry.function.isNotEmpty()) append(" in ${entry.function}")
                }

                // Add error code if present
                if (entry.error_code != 0) append(" [code=${entry.error_code}]")

                // Add model info if present
                if (entry.model_id.isNotEmpty() || entry.framework.isNotEmpty()) {
                    append(" [")
                    if (entry.model_id.isNotEmpty()) append("model=${entry.model_id}")
                    if (entry.model_id.isNotEmpty() && entry.framework.isNotEmpty()) append(", ")
                    if (entry.framework.isNotEmpty()) append("framework=${entry.framework}")
                    append("]")
                }
            }

        println(output)
    }

    // Metadata sanitization

    // Fallback sensitive-substring list used when the canonical C++ policy
    // (`rac_log_metadata_should_redact`) is not yet reachable — e.g. before
    // the native library is loaded or in non-JNI test contexts. Keep in
    // lockstep with `sdk/runanywhere-commons/src/infrastructure/logging/
    // log_redact.cpp` (kSensitiveSubstrings) and Swift `SDKLogger.swift`.
    private val sensitivePatterns = listOf("key", "secret", "password", "token", "auth", "credential")

    /**
     * Determines whether a metadata key should be redacted. Delegates to the
     * canonical C++ policy via [shouldRedactPolicy] when set; otherwise falls
     * back to the hardcoded [sensitivePatterns] list. Any error thrown by the
     * policy hook (e.g. `UnsatisfiedLinkError` if the native library is
     * unavailable) is swallowed and the fallback list is used so logging never
     * fails on metadata sanitization.
     */
    private fun shouldRedact(key: String): Boolean {
        val policy = shouldRedactPolicy
        if (policy != null) {
            try {
                return policy(key)
            } catch (_: Throwable) {
                // Fall through to hardcoded list — keeps logging resilient if
                // the native bridge is unavailable.
            }
        }
        val lowercasedKey = key.lowercase()
        return sensitivePatterns.any { lowercasedKey.contains(it) }
    }

    @Suppress("UNCHECKED_CAST")
    private fun sanitizeMetadata(metadata: Map<String, Any?>?): Map<String, String>? {
        if (metadata == null) return null

        return metadata.mapValues { (key, value) ->
            when {
                shouldRedact(key) -> "[REDACTED]"
                value is Map<*, *> -> sanitizeMetadata(value as? Map<String, Any?>)?.toString() ?: "{}"
                else -> value?.toString() ?: "null"
            }
        }
    }
}

// SDK logger (convenience wrapper)

/**
 * Simple logger for SDK components with category-based filtering.
 * Matches Swift SDK SDKLogger struct.
 */
class SDKLogger(
    val category: String = "SDK",
) {
    // Logging methods

    /**
     * Log a trace-level message (proto LOG_LEVEL_TRACE — the most verbose
     * severity, below DEBUG).
     */
    fun trace(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_TRACE,
            category = category,
            message = message,
            metadata = metadata,
        )
    }

    /**
     * Log a debug-level message.
     */
    fun debug(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_DEBUG,
            category = category,
            message = message,
            metadata = metadata,
        )
    }

    /**
     * Log an info-level message.
     */
    fun info(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_INFO,
            category = category,
            message = message,
            metadata = metadata,
        )
    }

    /**
     * Log a warning-level message.
     */
    fun warning(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_WARNING,
            category = category,
            message = message,
            metadata = metadata,
        )
    }

    /**
     * Alias for warning to match common conventions.
     */
    fun warn(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) = warning(message, metadata)

    /**
     * Log an error-level message.
     */
    fun error(
        message: String,
        metadata: Map<String, Any?>? = null,
        throwable: Throwable? = null,
    ) {
        val errorMetadata =
            if (throwable != null) {
                (metadata ?: emptyMap()) +
                    mapOf(
                        "exception_type" to throwable::class.simpleName,
                        "exception_message" to throwable.message,
                    )
            } else {
                metadata
            }

        Logging.log(
            level = LogLevel.LOG_LEVEL_ERROR,
            category = category,
            message = message,
            metadata = errorMetadata,
        )
    }

    /**
     * Log a fault-level message (critical system errors). Mirrors Swift's
     * top severity (`LogLevel.fault`).
     */
    fun fault(
        message: String,
        metadata: Map<String, Any?>? = null,
        throwable: Throwable? = null,
    ) {
        val faultMetadata =
            if (throwable != null) {
                (metadata ?: emptyMap()) +
                    mapOf(
                        "exception_type" to throwable::class.simpleName,
                        "exception_message" to throwable.message,
                    )
            } else {
                metadata
            }

        Logging.log(
            level = LogLevel.LOG_LEVEL_FATAL,
            category = category,
            message = message,
            metadata = faultMetadata,
        )
    }

    // Error logging with context

    /**
     * Log an error with source location context.
     */
    fun logError(
        error: Throwable,
        additionalInfo: String? = null,
        file: String? = null,
        line: Int? = null,
        function: String? = null,
    ) {
        val errorMessage =
            buildString {
                append(error.message ?: error::class.simpleName)
                if (file != null || line != null || function != null) {
                    append(" at ")
                    file?.let { append(it) }
                    line?.let { append(":$it") }
                    function?.let { append(" in $it") }
                }
                additionalInfo?.let { append(" | Context: $it") }
            }

        val metadata =
            buildMap<String, Any?> {
                file?.let { put("source_file", it) }
                line?.let { put("source_line", it) }
                function?.let { put("source_function", it) }
                put("exception_type", error::class.simpleName)
                put("exception_message", error.message)
            }

        Logging.log(
            level = LogLevel.LOG_LEVEL_ERROR,
            category = category,
            message = errorMessage,
            metadata = metadata,
            file = file,
            line = line,
            function = function,
        )
    }

    /**
     * Log with model context (for model-related operations).
     */
    fun logModelInfo(
        message: String,
        modelId: String,
        framework: String? = null,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_INFO,
            category = category,
            message = message,
            metadata = metadata,
            modelId = modelId,
            framework = framework,
        )
    }

    /**
     * Log model error with context.
     */
    fun logModelError(
        message: String,
        modelId: String,
        framework: String? = null,
        errorCode: Int? = null,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.LOG_LEVEL_ERROR,
            category = category,
            message = message,
            metadata = metadata,
            modelId = modelId,
            framework = framework,
            errorCode = errorCode,
        )
    }

    // Companion object — convenience loggers

    companion object {
        /**
         * Set the global minimum log level.
         */
        fun setLevel(level: LogLevel) {
            Logging.setMinLogLevel(level)
        }

        // CONVENIENCE LOGGERS (matching Swift SDK and runanywhere-commons)

        /** Shared logger for general SDK usage */
        val shared = SDKLogger("RunAnywhere")

        /** Logger for LLM operations */
        val llm = SDKLogger("LLM")

        /** Logger for STT (Speech-to-Text) operations */
        val stt = SDKLogger("STT")

        /** Logger for TTS (Text-to-Speech) operations */
        val tts = SDKLogger("TTS")

        /** Logger for VAD (Voice Activity Detection) operations */
        val vad = SDKLogger("VAD")

        /** Logger for model management operations */
        val models = SDKLogger("Models")

        /** Logger for ONNX runtime operations */
        val onnx = SDKLogger("ONNX")

        /** Logger for LlamaCpp operations */
        val llamacpp = SDKLogger("LlamaCpp")

        /** Logger for RAG (Retrieval-Augmented Generation) operations */
        val rag = SDKLogger("RAG")

        /** Logger for VoiceAgent operations */
        val voiceAgent = SDKLogger("VoiceAgent")
    }
}
