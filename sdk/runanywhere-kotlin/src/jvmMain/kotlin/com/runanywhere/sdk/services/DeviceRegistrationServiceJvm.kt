package com.runanywhere.sdk.services

import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.foundation.JvmDeviceInfoCollector
import java.lang.management.ManagementFactory
import java.net.InetAddress

/**
 * JVM-specific implementations for DeviceRegistrationService
 * Provides comprehensive device information collection for desktop/server environments
 */

/**
 * Get platform-specific device information for JVM
 */
actual fun getPlatformSpecificDeviceInfo(): Map<String, Any?> {
    val info = mutableMapOf<String, Any?>()
    val runtime = Runtime.getRuntime()

    try {
        // Basic device information
        info["device_name"] = try {
            InetAddress.getLocalHost().hostName
        } catch (e: Exception) {
            "JVM-Device"
        }

        info["system_name"] = System.getProperty("os.name", "Unknown OS")
        info["system_version"] = System.getProperty("os.version", "Unknown Version")
        info["model_name"] = "JVM ${System.getProperty("java.vm.name", "Unknown JVM")}"
        info["model_identifier"] = "${System.getProperty("java.vm.vendor", "Unknown")}-${System.getProperty("java.vm.version", "Unknown")}"

        // CPU information
        info["cpu_type"] = System.getProperty("java.vm.name", "Unknown CPU")
        info["cpu_architecture"] = System.getProperty("os.arch", "Unknown Architecture")
        info["cpu_core_count"] = runtime.availableProcessors()

        // Try to get CPU frequency if available
        try {
            val osBean = ManagementFactory.getOperatingSystemMXBean()
            // CPU frequency is not readily available through standard JVM APIs
            info["cpu_frequency_mhz"] = null
        } catch (e: Exception) {
            info["cpu_frequency_mhz"] = null
        }

        // Memory information (in MB)
        val maxMemory = runtime.maxMemory()
        val totalMemory = runtime.totalMemory()
        val freeMemory = runtime.freeMemory()
        val usedMemory = totalMemory - freeMemory
        val availableMemory = maxMemory - usedMemory

        info["total_memory_mb"] = maxMemory / (1024 * 1024)
        info["available_memory_mb"] = availableMemory / (1024 * 1024)

        // Storage information
        try {
            val rootPath = java.io.File("/")
            if (rootPath.exists()) {
                info["total_storage_mb"] = rootPath.totalSpace / (1024 * 1024)
                info["available_storage_mb"] = rootPath.freeSpace / (1024 * 1024)
            } else {
                // Fallback for Windows
                val userHome = java.io.File(System.getProperty("user.home"))
                info["total_storage_mb"] = userHome.totalSpace / (1024 * 1024)
                info["available_storage_mb"] = userHome.freeSpace / (1024 * 1024)
            }
        } catch (e: Exception) {
            info["total_storage_mb"] = 0L
            info["available_storage_mb"] = 0L
        }

        // GPU information (limited on JVM)
        info["gpu_type"] = GPUType.UNKNOWN
        info["gpu_name"] = null
        info["gpu_vendor"] = null
        info["supports_vulkan"] = false
        info["supports_opencl"] = false

        // Power and thermal (not available on JVM)
        info["battery_level"] = null
        info["battery_state"] = BatteryState.UNKNOWN
        info["thermal_state"] = ThermalState.NOMINAL
        info["is_low_power_mode"] = false

        // Network capabilities (assume available on desktop)
        info["has_cellular"] = false
        info["has_wifi"] = true  // Assume true for desktop
        info["has_bluetooth"] = false

        // I/O capabilities (assume available on desktop)
        info["has_camera"] = false  // Cannot determine without additional libraries
        info["has_microphone"] = true  // Assume true for desktop
        info["has_speakers"] = true   // Assume true for desktop
        info["has_biometric"] = false

        // Performance metrics
        info["benchmark_score"] = null  // Would require benchmarking
        info["memory_pressure"] = (usedMemory.toFloat() / maxMemory.toFloat()).coerceAtMost(1.0f)

        // Add comprehensive device info from collector
        val collectorInfo = JvmDeviceInfoCollector.collectDeviceInfo()
        info.putAll(collectorInfo.filterKeys { !info.containsKey(it) })

    } catch (e: Exception) {
        info["collection_error"] = e.message ?: "Unknown error"
    }

    return info
}

/**
 * Get platform-specific capabilities for JVM
 */
actual fun getPlatformCapabilities(): Map<String, Any> {
    return try {
        JvmDeviceInfoCollector.getDeviceCapabilities()
    } catch (e: Exception) {
        mapOf("error" to (e.message ?: "Unknown error"))
    }
}
