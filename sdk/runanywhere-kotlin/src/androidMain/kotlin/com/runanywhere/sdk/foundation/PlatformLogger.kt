package com.runanywhere.sdk.foundation

import android.util.Log

/**
 * Android implementation of PlatformLogger using Android Log.
 * Supports all log levels including TRACE and FAULT.
 */
actual class PlatformLogger actual constructor(
    private val tag: String,
) {
    /**
     * Log a trace-level message.
     * Maps to Android's VERBOSE level.
     */
    actual fun trace(message: String) {
        Log.v(tag, message)
    }

    /**
     * Log a debug-level message.
     */
    actual fun debug(message: String) {
        Log.d(tag, message)
    }

    /**
     * Log an info-level message.
     */
    actual fun info(message: String) {
        Log.i(tag, message)
    }

    /**
     * Log a warning-level message.
     */
    actual fun warning(message: String) {
        Log.w(tag, message)
    }

    /**
     * Log an error-level message.
     */
    actual fun error(
        message: String,
        throwable: Throwable?,
    ) {
        if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }

    /**
     * Log a fault-level message (critical system errors).
     * Maps to Android's WTF (What a Terrible Failure) level.
     */
    actual fun fault(
        message: String,
        throwable: Throwable?,
    ) {
        if (throwable != null) {
            Log.wtf(tag, message, throwable)
        } else {
            Log.wtf(tag, message)
        }
    }
}
