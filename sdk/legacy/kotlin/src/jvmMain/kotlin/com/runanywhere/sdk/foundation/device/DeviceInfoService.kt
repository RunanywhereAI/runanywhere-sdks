package com.runanywhere.sdk.foundation.device

import java.lang.management.ManagementFactory

/**
 * JVM implementation of DeviceInfoService
 *
 * Collects device information using Java System APIs
 */
actual class DeviceInfoService {
    actual fun getOSName(): String = System.getProperty("os.name") ?: "Unknown"

    actual fun getOSVersion(): String = System.getProperty("os.version") ?: "Unknown"

    actual fun getDeviceModel(): String {
        // JVM doesn't have a concept of device model, return generic label
        return try {
            "Desktop"
        } catch (e: Exception) {
            "Desktop"
        }
    }

    actual fun getChipName(): String? =
        try {
            System.getProperty("os.arch")
        } catch (e: Exception) {
            null
        }

    actual fun getTotalMemoryGB(): Double? =
        try {
            val osBean = ManagementFactory.getOperatingSystemMXBean()
            if (osBean is com.sun.management.OperatingSystemMXBean) {
                // Convert bytes to GB
                osBean.totalMemorySize / (1024.0 * 1024.0 * 1024.0)
            } else {
                // Fallback to Runtime max memory
                Runtime.getRuntime().maxMemory() / (1024.0 * 1024.0 * 1024.0)
            }
        } catch (e: Exception) {
            null
        }

    actual fun getTotalMemoryBytes(): Long? =
        try {
            val osBean = ManagementFactory.getOperatingSystemMXBean()
            if (osBean is com.sun.management.OperatingSystemMXBean) {
                osBean.totalMemorySize
            } else {
                // Fallback to Runtime max memory
                Runtime.getRuntime().maxMemory()
            }
        } catch (e: Exception) {
            null
        }

    actual fun getArchitecture(): String? =
        try {
            System.getProperty("os.arch")
        } catch (e: Exception) {
            null
        }
}
