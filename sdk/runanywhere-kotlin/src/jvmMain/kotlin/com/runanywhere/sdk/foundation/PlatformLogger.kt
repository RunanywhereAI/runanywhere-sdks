package com.runanywhere.sdk.foundation

/**
 * JVM implementation of PlatformLogger using println
 */
actual class PlatformLogger actual constructor(private val tag: String) {

    actual fun debug(message: String) {
        println("DEBUG[$tag]: $message")
    }

    actual fun info(message: String) {
        println("INFO[$tag]: $message")
    }

    actual fun warning(message: String) {
        println("WARN[$tag]: $message")
    }

    actual fun error(message: String, throwable: Throwable?) {
        println("ERROR[$tag]: $message")
        throwable?.printStackTrace()
    }
}
