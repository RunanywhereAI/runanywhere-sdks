package com.runanywhere.sdk.foundation.device

/**
 * Service for collecting device information
 *
 * Platform-specific implementations provide actual device details
 * Used for device registration and analytics
 */
expect class DeviceInfoService() {
    /**
     * Get operating system name (e.g., "Android", "Windows", "Linux")
     */
    fun getOSName(): String

    /**
     * Get operating system version (e.g., "13", "10.0.19044")
     */
    fun getOSVersion(): String

    /**
     * Get device model name (e.g., "Pixel 7", "Unknown")
     */
    fun getDeviceModel(): String

    /**
     * Get chip/CPU name (e.g., "ARM64", "x86_64")
     * Returns null if unable to determine
     */
    fun getChipName(): String?

    /**
     * Get total memory in GB
     * Returns null if unable to determine
     */
    fun getTotalMemoryGB(): Double?

    /**
     * Get total memory in bytes
     * Returns null if unable to determine
     */
    fun getTotalMemoryBytes(): Long?

    /**
     * Get device architecture (e.g., "ARM64", "x86_64")
     * Returns null if unable to determine
     */
    fun getArchitecture(): String?
}
