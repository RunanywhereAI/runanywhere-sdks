package com.runanywhere.sdk.infrastructure.device.services

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.telephony.TelephonyManager
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android-specific implementations for DeviceRegistrationService
 * Provides comprehensive device information collection using Android system APIs
 *
 * This file contains the actual implementations of the expect declarations in
 * commonMain for the DeviceRegistrationService.
 */

/**
 * Get platform-specific device information for Android
 */
actual fun getPlatformSpecificDeviceInfo(): Map<String, Any?> {
    val info = mutableMapOf<String, Any?>()

    try {
        val context = AndroidPlatformContext.applicationContext
        val runtime = Runtime.getRuntime()

        // Basic device information
        info["device_name"] = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        info["system_name"] = "Android"
        info["system_version"] = Build.VERSION.RELEASE
        info["model_name"] = Build.MODEL
        info["model_identifier"] = Build.DEVICE

        // CPU information
        info["cpu_type"] = Build.HARDWARE
        info["cpu_architecture"] =
            when {
                Build.SUPPORTED_64_BIT_ABIS.isNotEmpty() -> "arm64"
                Build.SUPPORTED_32_BIT_ABIS.isNotEmpty() -> "arm32"
                else -> Build.CPU_ABI ?: "unknown"
            }
        info["cpu_core_count"] = runtime.availableProcessors()
        info["cpu_frequency_mhz"] = getCpuFrequency() // Custom method to read CPU freq

        // Memory information
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        info["total_memory_mb"] = memoryInfo.totalMem / (1024 * 1024)
        info["available_memory_mb"] = memoryInfo.availMem / (1024 * 1024)

        // Storage information
        val (totalStorage, availableStorage) = getStorageInfo()
        info["total_storage_mb"] = totalStorage
        info["available_storage_mb"] = availableStorage

        // GPU information
        val (gpuType, gpuInfo) = getGpuInfo()
        info["gpu_type"] = gpuType
        info["gpu_name"] = gpuInfo["name"]
        info["gpu_vendor"] = gpuInfo["vendor"]
        info["supports_vulkan"] = checkVulkanSupport(context)
        info["supports_opencl"] = checkOpenCLSupport()

        // Battery information
        val batteryInfo = getBatteryInfo(context)
        info["battery_level"] = batteryInfo["level"]
        info["battery_state"] = batteryInfo["state"]
        info["is_low_power_mode"] = batteryInfo["isLowPowerMode"] ?: false

        // Thermal state
        info["thermal_state"] = getThermalState()

        // Network capabilities
        info["has_cellular"] = hasCellular(context)
        info["has_wifi"] = hasWifi(context)
        info["has_bluetooth"] = hasBluetooth(context)

        // I/O capabilities
        info["has_camera"] = hasCamera(context)
        info["has_microphone"] = hasMicrophone(context)
        info["has_speakers"] = hasSpeakers(context)
        info["has_biometric"] = hasBiometric(context)

        // Performance metrics
        info["benchmark_score"] = getDeviceBenchmarkScore()
        info["memory_pressure"] = getMemoryPressure(memoryInfo)

        // Add comprehensive device info from collector
        val collectorInfo = AndroidDeviceInfoCollector.collectDeviceInfo()
        info.putAll(collectorInfo.filterKeys { !info.containsKey(it) })
    } catch (e: Exception) {
        info["collection_error"] = e.message ?: "Unknown error"
    }

    return info
}

/**
 * Get platform-specific capabilities for Android
 */
actual fun getPlatformCapabilities(): Map<String, Any> =
    try {
        AndroidDeviceInfoCollector.getDeviceCapabilities()
    } catch (e: Exception) {
        mapOf("error" to (e.message ?: "Unknown error"))
    }

// MARK: - Private helper methods

/**
 * Get CPU frequency from /proc/cpuinfo if available
 */
private fun getCpuFrequency(): Int? =
    try {
        val cpuInfo = java.io.File("/proc/cpuinfo").readText()
        val freqLine = cpuInfo.lines().find { it.contains("cpu MHz") || it.contains("BogoMIPS") }
        freqLine
            ?.substringAfter(":")
            ?.trim()
            ?.substringBefore(" ")
            ?.toFloatOrNull()
            ?.toInt()
    } catch (e: Exception) {
        null
    }

/**
 * Get storage information
 */
private fun getStorageInfo(): Pair<Long, Long> =
    try {
        val stat = StatFs(Environment.getDataDirectory().path)
        val totalBytes = stat.blockCountLong * stat.blockSizeLong
        val availableBytes = stat.availableBlocksLong * stat.blockSizeLong

        Pair(
            totalBytes / (1024 * 1024), // Total storage in MB
            availableBytes / (1024 * 1024), // Available storage in MB
        )
    } catch (e: Exception) {
        Pair(0L, 0L)
    }

/**
 * Get GPU information
 */
private fun getGpuInfo(): Pair<GPUType, Map<String, String?>> {
    val gpuInfo = mutableMapOf<String, String?>()

    try {
        // Try to read GPU info from system properties
        val renderer = System.getProperty("ro.hardware.egl", "")
        val gpu = System.getProperty("ro.hardware.vulkan", "")

        gpuInfo["name"] = renderer.ifEmpty { gpu.ifEmpty { null } }
        gpuInfo["vendor"] = null // Not easily available

        // Determine GPU type based on known patterns
        val gpuType =
            when {
                renderer.contains("adreno", true) || gpu.contains("adreno", true) -> GPUType.ADRENO
                renderer.contains("mali", true) || gpu.contains("mali", true) -> GPUType.MALI
                renderer.contains("powervr", true) || gpu.contains("powervr", true) -> GPUType.POWER_VR
                renderer.contains("tegra", true) || gpu.contains("tegra", true) -> GPUType.TEGRA
                renderer.contains("vivante", true) || gpu.contains("vivante", true) -> GPUType.VIVANTE
                else -> GPUType.UNKNOWN
            }

        return Pair(gpuType, gpuInfo)
    } catch (e: Exception) {
        return Pair(GPUType.UNKNOWN, gpuInfo)
    }
}

/**
 * Check Vulkan support
 */
private fun checkVulkanSupport(context: Context): Boolean =
    try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL)
        } else {
            false
        }
    } catch (e: Exception) {
        false
    }

/**
 * Check OpenCL support (limited detection)
 */
private fun checkOpenCLSupport(): Boolean =
    try {
        // OpenCL support is harder to detect on Android
        // This is a basic check that can be improved
        java.io.File("/system/vendor/lib/libOpenCL.so").exists() ||
            java.io.File("/system/lib/libOpenCL.so").exists()
    } catch (e: Exception) {
        false
    }

/**
 * Get battery information
 */
private fun getBatteryInfo(context: Context): Map<String, Any?> {
    val batteryInfo = mutableMapOf<String, Any?>()

    try {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

        // Battery level (0.0 to 1.0)
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        batteryInfo["level"] = if (level >= 0) level / 100.0f else null

        // Battery state
        val status = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        batteryInfo["state"] =
            when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> BatteryState.CHARGING
                BatteryManager.BATTERY_STATUS_FULL -> BatteryState.FULL
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> BatteryState.UNPLUGGED
                else -> BatteryState.UNKNOWN
            }

        // Low power mode (Power Saver)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            batteryInfo["isLowPowerMode"] = powerManager.isPowerSaveMode
        } else {
            batteryInfo["isLowPowerMode"] = false
        }
    } catch (e: Exception) {
        batteryInfo["level"] = null
        batteryInfo["state"] = BatteryState.UNKNOWN
        batteryInfo["isLowPowerMode"] = false
    }

    return batteryInfo
}

/**
 * Get thermal state
 */
private fun getThermalState(): ThermalState =
    try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ has thermal API but it's restricted
            ThermalState.NOMINAL
        } else {
            ThermalState.NOMINAL
        }
    } catch (e: Exception) {
        ThermalState.NOMINAL
    }

/**
 * Check cellular capability
 */
private fun hasCellular(context: Context): Boolean =
    try {
        val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager.phoneType != TelephonyManager.PHONE_TYPE_NONE
    } catch (e: Exception) {
        false
    }

/**
 * Check WiFi capability
 */
private fun hasWifi(context: Context): Boolean =
    try {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI)
    } catch (e: Exception) {
        false
    }

/**
 * Check Bluetooth capability
 */
private fun hasBluetooth(context: Context): Boolean =
    try {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
    } catch (e: Exception) {
        false
    }

/**
 * Check camera capability
 */
private fun hasCamera(context: Context): Boolean =
    try {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    } catch (e: Exception) {
        false
    }

/**
 * Check microphone capability
 */
private fun hasMicrophone(context: Context): Boolean =
    try {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
    } catch (e: Exception) {
        false
    }

/**
 * Check speakers capability
 */
private fun hasSpeakers(context: Context): Boolean =
    try {
        // Most Android devices have speakers, check audio feature
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_AUDIO_OUTPUT)
    } catch (e: Exception) {
        true // Assume true if we can't check
    }

/**
 * Check biometric capability
 */
private fun hasBiometric(context: Context): Boolean =
    try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        } else {
            false
        }
    } catch (e: Exception) {
        false
    }

/**
 * Get basic device benchmark score
 */
private fun getDeviceBenchmarkScore(): Int? =
    try {
        // Simple benchmark based on known device characteristics
        val score =
            when {
                Build.VERSION.SDK_INT >= 33 -> 80 // Android 13+
                Build.VERSION.SDK_INT >= 30 -> 70 // Android 11+
                Build.VERSION.SDK_INT >= 26 -> 60 // Android 8+
                else -> 40
            }

        // Adjust based on RAM
        val runtime = Runtime.getRuntime()
        val memoryMB = runtime.maxMemory() / (1024 * 1024)
        val memoryBonus =
            when {
                memoryMB >= 8192 -> 20
                memoryMB >= 6144 -> 15
                memoryMB >= 4096 -> 10
                else -> 0
            }

        minOf(score + memoryBonus, 100)
    } catch (e: Exception) {
        null
    }

/**
 * Calculate memory pressure
 */
private fun getMemoryPressure(memoryInfo: ActivityManager.MemoryInfo): Float =
    try {
        val usedMemory = memoryInfo.totalMem - memoryInfo.availMem
        (usedMemory.toFloat() / memoryInfo.totalMem.toFloat()).coerceAtMost(1.0f)
    } catch (e: Exception) {
        0.0f
    }
