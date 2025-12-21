package com.runanywhere.sdk.public.errors

import com.runanywhere.sdk.utils.getCurrentTimeMillis

/**
 * JVM/Android implementation of error context capture.
 * Uses JVM StackTrace APIs for full stack trace information.
 */

// Patterns to filter out irrelevant stack frames
private val FILTER_PATTERNS = listOf(
    "kotlin.",
    "kotlinx.",
    "java.lang.",
    "java.util.",
    "jdk.internal.",
    "sun.",
    "ErrorContext",
    "captureErrorContext",
    "withContext",
    "getStackTrace",
)

/**
 * JVM/Android implementation of error context capture.
 * Provides full stack trace with file/line/function information.
 */
actual fun captureErrorContextPlatform(skipFrames: Int): ErrorContext {
    val stackTrace = Exception().stackTrace

    // Find the first relevant frame (skip internal frames)
    val relevantFrame = stackTrace.drop(skipFrames).firstOrNull { frame ->
        FILTER_PATTERNS.none { pattern -> frame.className.contains(pattern) }
    } ?: stackTrace.getOrNull(skipFrames) ?: StackTraceElement("Unknown", "unknown", "Unknown.kt", 0)

    // Filter and format stack trace
    val filteredStackTrace = stackTrace
        .drop(skipFrames)
        .filter { frame ->
            FILTER_PATTERNS.none { pattern -> frame.className.contains(pattern) }
        }
        .take(15) // Limit to 15 most relevant frames (matches iOS)
        .map { frame ->
            "${frame.className}.${frame.methodName}(${frame.fileName ?: "Unknown"}:${frame.lineNumber})"
        }

    return ErrorContext(
        file = relevantFrame.fileName ?: "Unknown",
        line = relevantFrame.lineNumber,
        function = "${relevantFrame.className.substringAfterLast('.')}.${relevantFrame.methodName}",
        stackTrace = filteredStackTrace,
        timestamp = getCurrentTimeMillis(),
        threadInfo = getCurrentThreadName(),
    )
}

/**
 * JVM/Android implementation of current thread name.
 */
actual fun getCurrentThreadName(): String {
    val thread = Thread.currentThread()
    return if (thread.name == "main") "main" else "${thread.name} (${thread.id})"
}
