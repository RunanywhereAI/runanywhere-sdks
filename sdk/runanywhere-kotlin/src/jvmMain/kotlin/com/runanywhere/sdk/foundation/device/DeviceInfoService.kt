package com.runanywhere.sdk.foundation.device

import java.lang.management.ManagementFactory

/**
 * JVM implementation of DeviceInfoService
 *
 * Collects device information using Java System APIs
 */
actual class DeviceInfoService {

    actual fun getOSName(): String {
        return System.getProperty("os.name") ?: "Unknown"
    }

    actual fun getOSVersion(): String {
        return System.getProperty("os.version") ?: "Unknown"
    }

    actual fun getDeviceModel(): String {
        // JVM doesn't have a concept of device model, use computer name or "Desktop"
        return try {
            System.getProperty("user.name")?.let { "Desktop ($it)" } ?: "Desktop"
        } catch (e: Exception) {
            "Desktop"
        }
    }

    actual fun getChipName(): String? {
        return try {
            System.getProperty("os.arch")
        } catch (e: Exception) {
            null
        }
    }

    actual fun getTotalMemoryGB(): Double? {
        return try {
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
    }
}
