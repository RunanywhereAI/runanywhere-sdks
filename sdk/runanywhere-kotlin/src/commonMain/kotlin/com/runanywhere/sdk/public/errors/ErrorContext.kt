package com.runanywhere.sdk.public.errors

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

/**
 * Context information for errors, matching iOS ErrorContext exactly.
 *
 * Captures:
 * - Stack trace information
 * - File, line, and function where error occurred
 * - Timestamp of when error was captured
 * - Thread information
 *
 * Usage:
 * ```kotlin
 * // Capture context at throw point
 * throw error.withContext()
 *
 * // Or manually capture context
 * val context = ErrorContext.capture()
 * throw ContextualError(error, context)
 * ```
 */
@Serializable
data class ErrorContext(
    /** File name where error occurred */
    val file: String,
    /** Line number where error occurred */
    val line: Int,
    /** Function/method name where error occurred */
    val function: String,
    /** Stack trace (filtered to relevant frames) */
    val stackTrace: List<String>,
    /** Timestamp when error was captured (epoch milliseconds) */
    val timestamp: Long = getCurrentTimeMillis(),
    /** Thread information (name or identifier) */
    val threadInfo: String,
) {
    /**
     * Formatted location string (matches iOS locationString)
     */
    val locationString: String
        get() = "$file:$line in $function"

    /**
     * Formatted stack trace for display (matches iOS formattedStackTrace)
     */
    val formattedStackTrace: String
        get() = stackTrace.joinToString("\n") { "  at $it" }

    /**
     * Full formatted context for logging
     */
    val formattedContext: String
        get() = buildString {
            appendLine("Location: $locationString")
            appendLine("Thread: $threadInfo")
            appendLine("Timestamp: $timestamp")
            if (stackTrace.isNotEmpty()) {
                appendLine("Stack trace:")
                appendLine(formattedStackTrace)
            }
        }

    companion object {
        /**
         * Capture error context at the current call site.
         * Matches iOS captureErrorContext() function.
         *
         * @param skipFrames Number of stack frames to skip (default 2 to skip capture methods)
         * @return ErrorContext with current location information
         */
        fun capture(skipFrames: Int = 2): ErrorContext = captureErrorContextPlatform(skipFrames)
    }
}

/**
 * Platform-specific error context capture.
 * Must be implemented in each platform's source set.
 */
expect fun captureErrorContextPlatform(skipFrames: Int): ErrorContext

/**
 * Platform-specific current thread name.
 */
expect fun getCurrentThreadName(): String

/**
 * Wrapper that attaches context to any throwable.
 * Matches iOS ContextualError struct.
 */
class ContextualError(
    /** The underlying error */
    val error: Throwable,
    /** Context captured when error was wrapped */
    val context: ErrorContext,
) : Exception(error.message, error) {
    override val message: String
        get() = "${error.message ?: error::class.simpleName} at ${context.locationString}"

    override fun toString(): String = buildString {
        appendLine("ContextualError: ${error::class.simpleName}")
        appendLine(context.formattedContext)
        appendLine("Underlying error: $error")
    }
}

/**
 * Extension to wrap any throwable with error context.
 * Matches iOS Error.withContext() extension.
 *
 * Usage:
 * ```kotlin
 * throw myError.withContext()
 * ```
 */
fun Throwable.withContext(skipFrames: Int = 3): ContextualError {
    // If already a ContextualError, return as-is
    if (this is ContextualError) return this

    return ContextualError(
        error = this,
        context = ErrorContext.capture(skipFrames),
    )
}

/**
 * Extension to extract error context from a throwable.
 * Matches iOS Error.errorContext extension.
 *
 * @return The error context if available, null otherwise
 */
val Throwable.errorContext: ErrorContext?
    get() = (this as? ContextualError)?.context

/**
 * Extension to get the underlying error value.
 * Matches iOS Error.underlyingErrorValue extension.
 *
 * @return The underlying error if this is a ContextualError, otherwise this
 */
val Throwable.underlyingError: Throwable
    get() = (this as? ContextualError)?.error ?: this

/**
 * Capture error context at the current call site.
 * Top-level function matching iOS captureErrorContext().
 */
fun captureErrorContext(skipFrames: Int = 2): ErrorContext = ErrorContext.capture(skipFrames)

/**
 * Log an error with full context.
 * Matches iOS logError() helper function.
 *
 * @param error The error to log
 * @param additionalInfo Additional information to include in the log
 */
fun logError(
    error: Throwable,
    additionalInfo: Map<String, Any> = emptyMap(),
) {
    val context = error.errorContext ?: ErrorContext.capture(skipFrames = 3)
    val underlying = error.underlyingError

    val logMessage = buildString {
        appendLine("ERROR: ${underlying::class.simpleName}")
        appendLine("Message: ${underlying.message}")
        appendLine("Location: ${context.locationString}")
        appendLine("Thread: ${context.threadInfo}")
        if (additionalInfo.isNotEmpty()) {
            appendLine("Additional Info:")
            additionalInfo.forEach { (key, value) ->
                appendLine("  $key: $value")
            }
        }
        appendLine("Stack trace:")
        appendLine(context.formattedStackTrace)
    }

    // Log using SDK logger
    SDKLogger("ErrorContext").error(logMessage)
}
