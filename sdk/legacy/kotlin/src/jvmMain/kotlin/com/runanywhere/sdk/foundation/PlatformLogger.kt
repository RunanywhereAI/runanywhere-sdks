package com.runanywhere.sdk.foundation

/**
 * JVM implementation of PlatformLogger using println.
 * Supports all log levels including TRACE and FAULT.
 */
actual class PlatformLogger actual constructor(
    private val tag: String,
) {
    /**
     * Log a trace-level message.
     */
    actual fun trace(message: String) {
        println("TRACE[$tag]: $message")
    }

    /**
     * Log a debug-level message.
     */
    actual fun debug(message: String) {
        println("DEBUG[$tag]: $message")
    }

    /**
     * Log an info-level message.
     */
    actual fun info(message: String) {
        println("INFO[$tag]: $message")
    }

    /**
     * Log a warning-level message.
     */
    actual fun warning(message: String) {
        println("WARN[$tag]: $message")
    }

    /**
     * Log an error-level message.
     */
    actual fun error(
        message: String,
        throwable: Throwable?,
    ) {
        println("ERROR[$tag]: $message")
        throwable?.printStackTrace()
    }

    /**
     * Log a fault-level message (critical system errors).
     * Outputs to stderr for maximum visibility.
     */
    actual fun fault(
        message: String,
        throwable: Throwable?,
    ) {
        System.err.println("FAULT[$tag]: $message")
        throwable?.printStackTrace(System.err)
    }
}
