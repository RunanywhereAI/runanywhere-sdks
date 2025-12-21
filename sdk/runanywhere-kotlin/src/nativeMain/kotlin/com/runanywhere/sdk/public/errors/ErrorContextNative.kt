package com.runanywhere.sdk.public.errors

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlin.native.concurrent.Worker

/**
 * Native platform implementation of error context capture.
 * Native platforms have limited stack trace support, so we provide
 * a basic implementation that captures what's available.
 */

/**
 * Native implementation of error context capture.
 * Provides limited stack trace information due to platform constraints.
 */
actual fun captureErrorContextPlatform(skipFrames: Int): ErrorContext {
    // Native platforms have limited stack trace support
    // We capture what we can from the exception

    val exception = Exception("Context capture")
    val stackTrace = exception.getStackTrace()

    // Parse available stack trace elements
    val filteredStackTrace = stackTrace
        .drop(skipFrames)
        .take(15)
        .toList()

    // Try to extract file/line/function from first relevant frame
    val firstFrame = filteredStackTrace.firstOrNull() ?: "Unknown.unknown(Unknown.kt:0)"

    // Parse the frame string - typical format: "package.Class.method(File.kt:line)"
    val functionMatch = Regex("""(.+?)\.(\w+)\((.+?):(\d+)\)""").find(firstFrame)
    val file = functionMatch?.groupValues?.getOrNull(3) ?: "Unknown"
    val line = functionMatch?.groupValues?.getOrNull(4)?.toIntOrNull() ?: 0
    val function = if (functionMatch != null) {
        "${functionMatch.groupValues[1].substringAfterLast('.')}.${functionMatch.groupValues[2]}"
    } else {
        "unknown"
    }

    return ErrorContext(
        file = file,
        line = line,
        function = function,
        stackTrace = filteredStackTrace,
        timestamp = getCurrentTimeMillis(),
        threadInfo = getCurrentThreadName(),
    )
}

/**
 * Native implementation of current thread name.
 */
actual fun getCurrentThreadName(): String {
    return try {
        // Try to get worker name if running on a worker
        Worker.current.name
    } catch (e: Exception) {
        "main"
    }
}
