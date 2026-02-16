package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// =============================================================================
// LOG LEVEL
// =============================================================================

/**
 * Log severity levels matching runanywhere-commons and Swift SDK.
 * Ordered from least to most severe.
 */
enum class LogLevel(
    val value: Int,
) : Comparable<LogLevel> {
    TRACE(0),
    DEBUG(1),
    INFO(2),
    WARNING(3),
    ERROR(4),
    FAULT(5),
    ;

    override fun toString(): String =
        when (this) {
            TRACE -> "trace"
            DEBUG -> "debug"
            INFO -> "info"
            WARNING -> "warning"
            ERROR -> "error"
            FAULT -> "fault"
        }

    companion object {
        fun fromValue(value: Int): LogLevel = entries.find { it.value == value } ?: INFO
    }
}

// =============================================================================
// LOG ENTRY
// =============================================================================

/**
 * Represents a single log message with metadata.
 * Matches Swift SDK LogEntry structure.
 */
data class LogEntry(
    val timestamp: SimpleInstant = SimpleInstant.now(),
    val level: LogLevel,
    val category: String,
    val message: String,
    val metadata: Map<String, String>? = null,
    val file: String? = null,
    val line: Int? = null,
    val function: String? = null,
    val errorCode: Int? = null,
    val modelId: String? = null,
    val framework: String? = null,
)

// =============================================================================
// LOG DESTINATION PROTOCOL
// =============================================================================

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

// =============================================================================
// LOGGING CONFIGURATION
// =============================================================================

/**
 * Configuration for the logging system.
 * Matches Swift SDK LoggingConfiguration structure.
 */
data class LoggingConfiguration(
    val enableLocalLogging: Boolean = true,
    val minLogLevel: LogLevel = LogLevel.INFO,
    val includeSourceLocation: Boolean = false,
    val enableRemoteLogging: Boolean = false,
    val enableSentryLogging: Boolean = false,
    val includeDeviceMetadata: Boolean = false,
) {
    companion object {
        /**
         * Development environment preset.
         * Enables debug logging and detailed source location.
         */
        val development =
            LoggingConfiguration(
                enableLocalLogging = true,
                minLogLevel = LogLevel.DEBUG,
                includeSourceLocation = true,
                enableRemoteLogging = false,
                enableSentryLogging = false,
                includeDeviceMetadata = true,
            )

        /**
         * Staging environment preset.
         * Info level with source location for debugging.
         */
        val staging =
            LoggingConfiguration(
                enableLocalLogging = true,
                minLogLevel = LogLevel.INFO,
                includeSourceLocation = true,
                enableRemoteLogging = false,
                enableSentryLogging = true,
                includeDeviceMetadata = true,
            )

        /**
         * Production environment preset.
         * Warning level and above, Sentry enabled for error tracking.
         */
        val production =
            LoggingConfiguration(
                enableLocalLogging = false,
                minLogLevel = LogLevel.WARNING,
                includeSourceLocation = false,
                enableRemoteLogging = false,
                enableSentryLogging = true,
                includeDeviceMetadata = true,
            )

        /**
         * Get configuration for a specific environment.
         */
        fun forEnvironment(environment: SDKEnvironment): LoggingConfiguration =
            when (environment) {
                SDKEnvironment.DEVELOPMENT -> development
                SDKEnvironment.STAGING -> staging
                SDKEnvironment.PRODUCTION -> production
            }
    }
}

/**
 * SDK Environment for configuration selection.
 */
enum class SDKEnvironment {
    DEVELOPMENT,
    STAGING,
    PRODUCTION,
}

// =============================================================================
// LOGGING (CENTRAL SERVICE)
// =============================================================================

/**
 * Central logging service that routes logs to multiple destinations.
 * Thread-safe using Mutex for state management.
 * Matches Swift SDK Logging class.
 */
object Logging {
    private val mutex = Mutex()

    // Thread-safe state
    private var _configuration: LoggingConfiguration = LoggingConfiguration.development
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

    // =============================================================================
    // CONFIGURATION
    // =============================================================================

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
        configure(LoggingConfiguration.forEnvironment(environment))
    }

    /**
     * Set whether local logging is enabled.
     */
    fun setLocalLoggingEnabled(enabled: Boolean) {
        _configuration = _configuration.copy(enableLocalLogging = enabled)
    }

    /**
     * Set the minimum log level.
     */
    fun setMinLogLevel(level: LogLevel) {
        _configuration = _configuration.copy(minLogLevel = level)
    }

    /**
     * Set whether to include source location in logs.
     */
    fun setIncludeSourceLocation(include: Boolean) {
        _configuration = _configuration.copy(includeSourceLocation = include)
    }

    /**
     * Set whether to include device metadata in logs.
     */
    fun setIncludeDeviceMetadata(include: Boolean) {
        _configuration = _configuration.copy(includeDeviceMetadata = include)
    }

    /**
     * Set whether Sentry logging is enabled.
     * When enabled, warning+ logs are sent to Sentry for error tracking.
     *
     * Note: Call setupSentry() after enabling to initialize the Sentry SDK.
     */
    fun setSentryLoggingEnabled(enabled: Boolean) {
        val oldConfig = _configuration
        _configuration = _configuration.copy(enableSentryLogging = enabled)

        // Handle Sentry state changes via the platform-specific hook
        if (enabled && !oldConfig.enableSentryLogging) {
            sentrySetupHook?.invoke()
        } else if (!enabled && oldConfig.enableSentryLogging) {
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
     * Set the bridge callback for forwarding logs to runanywhere-commons.
     * This enables integration with the C/C++ logging system.
     */
    fun setCommonsLogBridge(bridge: ((LogEntry) -> Unit)?) {
        commonsLogBridge = bridge
    }

    // =============================================================================
    // CORE LOGGING
    // =============================================================================

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

        // Check if level meets minimum threshold
        if (level < config.minLogLevel) return

        // Check if any logging is enabled
        if (!config.enableLocalLogging && !config.enableRemoteLogging && _destinations.isEmpty()) return

        // Create log entry
        val entry =
            LogEntry(
                level = level,
                category = category,
                message = message,
                metadata = sanitizeMetadata(metadata),
                file = if (config.includeSourceLocation) file else null,
                line = if (config.includeSourceLocation) line else null,
                function = if (config.includeSourceLocation) function else null,
                errorCode = errorCode,
                modelId = modelId,
                framework = framework,
            )

        // Write to console if local logging enabled
        if (config.enableLocalLogging) {
            printToConsole(entry)
        }

        // Forward to runanywhere-commons bridge if set
        commonsLogBridge?.invoke(entry)

        // Write to all registered destinations
        for (destination in _destinations) {
            if (destination.isAvailable) {
                destination.write(entry)
            }
        }
    }

    // =============================================================================
    // DESTINATION MANAGEMENT
    // =============================================================================

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

    // =============================================================================
    // PRIVATE HELPERS
    // =============================================================================

    private fun printToConsole(entry: LogEntry) {
        val levelIndicator =
            when (entry.level) {
                LogLevel.TRACE -> "[TRACE]"
                LogLevel.DEBUG -> "[DEBUG]"
                LogLevel.INFO -> "[INFO]"
                LogLevel.WARNING -> "[WARN]"
                LogLevel.ERROR -> "[ERROR]"
                LogLevel.FAULT -> "[FAULT]"
            }

        val output =
            buildString {
                append(levelIndicator)
                append(" [")
                append(entry.category)
                append("] ")
                append(entry.message)

                // Add metadata if present
                entry.metadata?.takeIf { it.isNotEmpty() }?.let { meta ->
                    append(" | ")
                    append(meta.entries.joinToString(", ") { "${it.key}=${it.value}" })
                }

                // Add source location if present
                if (entry.file != null || entry.function != null) {
                    append(" @ ")
                    entry.file?.let { append(it) }
                    entry.line?.let { append(":$it") }
                    entry.function?.let { append(" in $it") }
                }

                // Add error code if present
                entry.errorCode?.let { append(" [code=$it]") }

                // Add model info if present
                if (entry.modelId != null || entry.framework != null) {
                    append(" [")
                    entry.modelId?.let { append("model=$it") }
                    if (entry.modelId != null && entry.framework != null) append(", ")
                    entry.framework?.let { append("framework=$it") }
                    append("]")
                }
            }

        println(output)
    }

    // =============================================================================
    // METADATA SANITIZATION
    // =============================================================================

    private val sensitivePatterns = listOf("key", "secret", "password", "token", "auth", "credential")

    @Suppress("UNCHECKED_CAST")
    private fun sanitizeMetadata(metadata: Map<String, Any?>?): Map<String, String>? {
        if (metadata == null) return null

        return metadata.mapValues { (key, value) ->
            val lowercasedKey = key.lowercase()
            when {
                sensitivePatterns.any { lowercasedKey.contains(it) } -> "[REDACTED]"
                value is Map<*, *> -> sanitizeMetadata(value as? Map<String, Any?>)?.toString() ?: "{}"
                else -> value?.toString() ?: "null"
            }
        }
    }
}

// =============================================================================
// PLATFORM LOGGER INTERFACE
// =============================================================================

/**
 * Platform-specific logger interface.
 * Implementations provided in androidMain and jvmMain.
 */
expect class PlatformLogger(
    tag: String,
) {
    fun trace(message: String)

    fun debug(message: String)

    fun info(message: String)

    fun warning(message: String)

    fun error(message: String, throwable: Throwable? = null)

    fun fault(message: String, throwable: Throwable? = null)
}

// =============================================================================
// SDK LOGGER (CONVENIENCE WRAPPER)
// =============================================================================

/**
 * Simple logger for SDK components with category-based filtering.
 * Matches Swift SDK SDKLogger struct.
 */
class SDKLogger(
    val category: String = "SDK",
) {
    // =============================================================================
    // LOGGING METHODS
    // =============================================================================

    /**
     * Log a trace-level message.
     */
    fun trace(
        message: String,
        metadata: Map<String, Any?>? = null,
    ) {
        Logging.log(
            level = LogLevel.TRACE,
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
            level = LogLevel.DEBUG,
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
            level = LogLevel.INFO,
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
            level = LogLevel.WARNING,
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
            level = LogLevel.ERROR,
            category = category,
            message = message,
            metadata = errorMetadata,
        )
    }

    /**
     * Log a fault-level message (critical system errors).
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
            level = LogLevel.FAULT,
            category = category,
            message = message,
            metadata = faultMetadata,
        )
    }

    // =============================================================================
    // ERROR LOGGING WITH CONTEXT
    // =============================================================================

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
            level = LogLevel.ERROR,
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
            level = LogLevel.INFO,
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
            level = LogLevel.ERROR,
            category = category,
            message = message,
            metadata = metadata,
            modelId = modelId,
            framework = framework,
            errorCode = errorCode,
        )
    }

    // =============================================================================
    // COMPANION OBJECT - CONVENIENCE LOGGERS
    // =============================================================================

    companion object {
        /**
         * Set the global minimum log level.
         */
        fun setLevel(level: LogLevel) {
            Logging.setMinLogLevel(level)
        }

        // =============================================================================
        // CONVENIENCE LOGGERS (matching Swift SDK and runanywhere-commons)
        // =============================================================================

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

        /** Logger for VLM (Vision Language Model) operations */
        val vlm = SDKLogger("VLM")

        /** Logger for download operations */
        val download = SDKLogger("Download")

        /** Logger for model management operations */
        val models = SDKLogger("Models")

        /** Logger for core SDK operations */
        val core = SDKLogger("Core")

        /** Logger for ONNX runtime operations */
        val onnx = SDKLogger("ONNX")

        /** Logger for LlamaCpp operations */
        val llamacpp = SDKLogger("LlamaCpp")

        /** Logger for VoiceAgent operations */
        val voiceAgent = SDKLogger("VoiceAgent")

        /** Logger for network operations */
        val network = SDKLogger("Network")
    }
}
