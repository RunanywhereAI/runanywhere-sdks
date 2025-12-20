package com.runanywhere.sdk.services

import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.foundation.JvmDeviceInfoCollector
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
        // Determine platform and form factor
        val osName = System.getProperty("os.name", "Unknown OS").lowercase()
        val platform =
            when {
                osName.contains("win") -> "windows"
                osName.contains("mac") -> "macos"
                osName.contains("linux") -> "linux"
                else -> "linux"
            }
        val formFactor = "desktop" // JVM typically runs on desktop/laptop

        info["platform"] = platform
        info["form_factor"] = formFactor

        // Basic device information
        info["device_name"] =
            try {
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

        // Map architecture to expected values
        val osArch = System.getProperty("os.arch", "unknown").lowercase()
        val architecture =
            when {
                osArch.contains("aarch64") || osArch.contains("arm64") -> "arm64"
                osArch.contains("x86_64") || osArch.contains("amd64") -> "x86_64"
                else -> "unknown"
            }
        info["cpu_architecture"] = architecture
        info["cpu_core_count"] = runtime.availableProcessors()

        // CPU frequency is not readily available through standard JVM APIs
        info["cpu_frequency_mhz"] = null

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
        info["gpu_family"] = "none" // Add gpu_family field
        info["supports_vulkan"] = false
        info["supports_opencl"] = false
        info["has_neural_engine"] = false
        info["neural_engine_cores"] = 0

        // Power and thermal (desktop defaults)
        info["battery_level"] = 1.0f // Full for desktop
        info["battery_state"] = BatteryState.FULL // Desktop is plugged in
        info["thermal_state"] = ThermalState.NOMINAL
        info["is_low_power_mode"] = false

        // Network capabilities (assume available on desktop)
        info["has_cellular"] = false
        info["has_wifi"] = true // Assume true for desktop
        info["has_bluetooth"] = false

        // I/O capabilities (assume available on desktop)
        info["has_camera"] = false // Cannot determine without additional libraries
        info["has_microphone"] = true // Assume true for desktop
        info["has_speakers"] = true // Assume true for desktop
        info["has_biometric"] = false

        // Performance metrics
        info["benchmark_score"] = null // Would require benchmarking
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
actual fun getPlatformCapabilities(): Map<String, Any> =
    try {
        JvmDeviceInfoCollector.getDeviceCapabilities()
    } catch (e: Exception) {
        mapOf("error" to (e.message ?: "Unknown error"))
    }
