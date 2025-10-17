package com.runanywhere.sdk.utils

/**
 * Platform-specific utilities
 */
expect object PlatformUtils {
    /**
     * Get a persistent device identifier
     */
    fun getDeviceId(): String

    /**
     * Get the platform name (e.g., "android", "jvm", "ios")
     */
    fun getPlatformName(): String

    /**
     * Get device information as key-value pairs
     */
    fun getDeviceInfo(): Map<String, String>

    /**
     * Get OS version
     */
    fun getOSVersion(): String

    /**
     * Get device model
     */
    fun getDeviceModel(): String

    /**
     * Get app version if available
     */
    fun getAppVersion(): String?
}

/**
 * Secure storage implementation for each platform
 */
expect class SecureStorageImpl() : com.runanywhere.sdk.storage.SecureStorage
