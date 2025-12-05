package com.runanywhere.sdk.capabilities.device

/**
 * Platform-specific system information provider
 *
 * Provides access to system info that varies by platform (JVM, Android, etc.)
 */
expect object PlatformSystemInfo {
    /**
     * Get the number of available processor cores
     */
    fun getAvailableProcessors(): Int

    /**
     * Get the amount of free memory in bytes
     */
    fun getFreeMemory(): Long

    /**
     * Get the total memory available to the runtime in bytes
     */
    fun getTotalMemory(): Long

    /**
     * Get the maximum memory the runtime will attempt to use in bytes
     */
    fun getMaxMemory(): Long

    /**
     * Get the operating system name
     */
    fun getOSName(): String

    /**
     * Get the operating system version string
     */
    fun getOSVersion(): String

    /**
     * Get the processor architecture
     */
    fun getArchitecture(): String
}
