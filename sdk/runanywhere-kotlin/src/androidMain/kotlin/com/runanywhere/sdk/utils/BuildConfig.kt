package com.runanywhere.sdk.utils

/**
 * Android implementation of BuildConfig
 */
actual object BuildConfig {
    actual val DEBUG: Boolean = true // Can be configured based on build type
    actual val VERSION_NAME: String = "1.0.0"
    actual val APPLICATION_ID: String = "com.runanywhere.sdk"
}
