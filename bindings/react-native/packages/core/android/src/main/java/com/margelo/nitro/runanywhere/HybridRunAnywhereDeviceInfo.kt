/**
 * HybridRunAnywhereDeviceInfo.kt
 *
 * Android implementation of device information for RunAnywhere SDK.
 * Provides device capabilities, memory info, and battery status.
 */

package com.margelo.nitro.runanywhere

import android.app.ActivityManager
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import java.io.BufferedReader
import java.io.File
import java.io.FileReader

/**
 * Kotlin implementation of RunAnywhereDeviceInfo HybridObject.
 * Provides device information and capabilities for the RunAnywhere SDK on Android.
 */
class HybridRunAnywhereDeviceInfo : HybridRunAnywhereDeviceInfoSpec() {

    companion object {
        private val logger = SDKLogger.core
    }

    private val context = NitroModules.applicationContext ?: error("Android context not found")

    /**
     * Get device model name
     */
    override fun getDeviceModel(): Promise<String> = Promise.async {
        val manufacturer = Build.MANUFACTURER
        val model = Build.MODEL
        if (model.startsWith(manufacturer, ignoreCase = true)) {
            model.capitalize()
        } else {
            "${manufacturer.capitalize()} $model"
        }
    }

    /**
     * Get OS version
     */
    override fun getOSVersion(): Promise<String> = Promise.async {
        Build.VERSION.RELEASE
    }

    /**
     * Get platform name
     */
    override fun getPlatform(): Promise<String> = Promise.async {
        "android"
    }

    /**
     * Get total RAM in bytes
     */
    override fun getTotalRAM(): Promise<Double> = Promise.async {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        memInfo.totalMem.toDouble()
    }

    /**
     * Get available RAM in bytes
     */
    override fun getAvailableRAM(): Promise<Double> = Promise.async {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        memInfo.availMem.toDouble()
    }

    /**
     * Get number of CPU cores
     */
    override fun getCPUCores(): Promise<Double> = Promise.async {
        Runtime.getRuntime().availableProcessors().toDouble()
    }

    /**
     * Check if device has GPU acceleration
     */
    override fun hasGPU(): Promise<Boolean> = Promise.async {
        // Check for Vulkan support as indicator of modern GPU
        val hasVulkan = try {
            val pm = context.packageManager
            pm.hasSystemFeature("android.hardware.vulkan.level")
        } catch (e: Exception) {
            false
        }

        // Most Android devices have some GPU
        hasVulkan || Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP
    }

    /**
     * Check if device has Neural Engine / NPU
     */
    override fun hasNPU(): Promise<Boolean> = Promise.async {
        // Android Neural Networks API (NNAPI) is available on API 27+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val hardware = Build.HARDWARE.lowercase()
            val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MODEL.lowercase()
            } else {
                ""
            }

            listOf(
                "qcom",      // Qualcomm (Hexagon DSP)
                "exynos",    // Samsung (NPU)
                "tensor",    // Google (TPU)
                "kirin",     // Huawei (NPU)
                "dimensity", // MediaTek (APU)
                "mtk"        // MediaTek
            ).any { hardware.contains(it) || soc.contains(it) }
        } else {
            false
        }
    }

    /**
     * Get chip name if available
     */
    override fun getChipName(): Promise<String> = Promise.async {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val socModel = Build.SOC_MODEL
            val socManufacturer = Build.SOC_MANUFACTURER
            if (socModel.isNotEmpty() && socModel != "unknown") {
                if (socManufacturer.isNotEmpty() && socManufacturer != "unknown") {
                    "$socManufacturer $socModel"
                } else {
                    socModel
                }
            } else {
                getCPUInfo()
            }
        } else {
            getCPUInfo()
        }
    }

    /**
     * Get device thermal state (0 = nominal, 1 = fair, 2 = serious, 3 = critical)
     */
    override fun getThermalState(): Promise<Double> = Promise.async {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            when (powerManager.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> 0.0
                PowerManager.THERMAL_STATUS_LIGHT -> 0.0
                PowerManager.THERMAL_STATUS_MODERATE -> 1.0
                PowerManager.THERMAL_STATUS_SEVERE -> 2.0
                PowerManager.THERMAL_STATUS_CRITICAL -> 3.0
                PowerManager.THERMAL_STATUS_EMERGENCY -> 3.0
                PowerManager.THERMAL_STATUS_SHUTDOWN -> 3.0
                else -> 0.0
            }
        } else {
            0.0
        }
    }

    /**
     * Get battery level (0.0 to 1.0)
     */
    override fun getBatteryLevel(): Promise<Double> = Promise.async {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        level.toDouble() / 100.0
    }

    /**
     * Check if device is charging
     */
    override fun isCharging(): Promise<Boolean> = Promise.async {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        batteryManager.isCharging
    }

    /**
     * Check if low power mode is enabled
     */
    override fun isLowPowerMode(): Promise<Boolean> = Promise.async {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        powerManager.isPowerSaveMode
    }

    /**
     * Read CPU info from /proc/cpuinfo
     */
    private fun getCPUInfo(): String {
        return try {
            val cpuInfo = File("/proc/cpuinfo")
            if (cpuInfo.exists()) {
                BufferedReader(FileReader(cpuInfo)).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        if (line?.startsWith("Hardware") == true) {
                            return line?.substringAfter(":")?.trim() ?: "Unknown"
                        }
                        if (line?.startsWith("model name") == true) {
                            return line?.substringAfter(":")?.trim() ?: "Unknown"
                        }
                    }
                }
            }
            Build.HARDWARE
        } catch (e: Exception) {
            logger.warning("Failed to read CPU info: ${e.message}")
            Build.HARDWARE
        }
    }

    private fun String.capitalize(): String {
        return if (isNotEmpty()) {
            this[0].uppercaseChar() + substring(1)
        } else {
            this
        }
    }
}
