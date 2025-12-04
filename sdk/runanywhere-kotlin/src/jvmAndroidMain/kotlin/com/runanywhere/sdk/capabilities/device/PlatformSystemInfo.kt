package com.runanywhere.sdk.capabilities.device

/**
 * JVM/Android platform-specific system information provider
 */
actual object PlatformSystemInfo {
    private val runtime: Runtime = Runtime.getRuntime()

    /**
     * Get the number of available processor cores
     */
    actual fun getAvailableProcessors(): Int = runtime.availableProcessors()

    /**
     * Get the amount of free memory in bytes
     */
    actual fun getFreeMemory(): Long = runtime.freeMemory()

    /**
     * Get the total memory available to the runtime in bytes
     */
    actual fun getTotalMemory(): Long = runtime.totalMemory()

    /**
     * Get the maximum memory the runtime will attempt to use in bytes
     */
    actual fun getMaxMemory(): Long = runtime.maxMemory()

    /**
     * Get the operating system name
     */
    actual fun getOSName(): String = System.getProperty("os.name") ?: "Unknown"

    /**
     * Get the operating system version string
     */
    actual fun getOSVersion(): String = System.getProperty("os.version") ?: "0.0.0"

    /**
     * Get the processor architecture
     */
    actual fun getArchitecture(): String = System.getProperty("os.arch") ?: "unknown"
}
