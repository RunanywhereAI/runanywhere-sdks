package com.runanywhere.sdk.utils

/**
 * JVM implementation of BuildConfig
 */
actual object BuildConfig {
    actual val DEBUG: Boolean = System.getProperty("debug", "false").toBoolean()
    actual val VERSION_NAME: String = SharedBuildConfig.VERSION_NAME
    actual val APPLICATION_ID: String = SharedBuildConfig.APPLICATION_ID
}
