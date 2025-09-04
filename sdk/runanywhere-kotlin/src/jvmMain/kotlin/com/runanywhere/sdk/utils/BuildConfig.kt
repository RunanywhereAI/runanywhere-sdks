package com.runanywhere.sdk.utils

/**
 * JVM implementation of BuildConfig
 */
actual object BuildConfig {
    actual val DEBUG: Boolean = System.getProperty("debug", "false").toBoolean()
    actual val VERSION_NAME: String = "1.0.0"
    actual val APPLICATION_ID: String = "com.runanywhere.sdk"
}
