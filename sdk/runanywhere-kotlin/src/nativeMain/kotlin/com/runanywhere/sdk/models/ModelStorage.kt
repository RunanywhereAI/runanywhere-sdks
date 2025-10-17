package com.runanywhere.sdk.models

import kotlinx.cinterop.toKString
import platform.posix.getenv

/**
 * Native implementation of platform-specific base directory
 */
actual fun getPlatformBaseDir(): String {
    // Try to get user home directory from environment
    val home = getenv("HOME")?.toKString()

    return home ?: "/tmp" // fallback to /tmp if HOME is not set
}
