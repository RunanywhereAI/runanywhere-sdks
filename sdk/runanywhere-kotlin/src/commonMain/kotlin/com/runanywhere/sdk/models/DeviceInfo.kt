package com.runanywhere.sdk.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

/**
 * Simplified DeviceInfo model matching iOS initialization requirements
 * This is separate from the more detailed DeviceInfoData model for basic initialization needs
 */
@Serializable
data class DeviceInfo(
    // Platform identification
    @SerialName("platform_name")
    val platformName: String, // "Android", "JVM", "Native"

    @SerialName("platform_version")
    val platformVersion: String, // Android API level, JVM version, etc.

    @SerialName("device_model")
    val deviceModel: String, // Device model name

    // Operating System
    @SerialName("os_version")
    val osVersion: String, // OS version string

    @SerialName("sdk_version")
    val sdkVersion: String, // RunAnywhere SDK version

    // Hardware basics
    @SerialName("cpu_cores")
    val cpuCores: Int, // Number of CPU cores

    @SerialName("total_memory_mb")
    val totalMemoryMB: Long, // Total RAM in MB

    // App information
    @SerialName("app_bundle_id")
    val appBundleId: String?, // Application bundle identifier

    @SerialName("app_version")
    val appVersion: String?, // Application version

    // Collection timestamp
    @SerialName("collected_at")
    val collectedAt: Long = System.currentTimeMillis()
) {
    companion object {
        /**
         * Create DeviceInfo from platform-specific implementations
         */
        fun create(
            platformName: String,
            platformVersion: String,
            deviceModel: String,
            osVersion: String,
            sdkVersion: String = "0.1.0",
            cpuCores: Int,
            totalMemoryMB: Long,
            appBundleId: String? = null,
            appVersion: String? = null
        ): DeviceInfo {
            return DeviceInfo(
                platformName = platformName,
                platformVersion = platformVersion,
                deviceModel = deviceModel,
                osVersion = osVersion,
                sdkVersion = sdkVersion,
                cpuCores = cpuCores,
                totalMemoryMB = totalMemoryMB,
                appBundleId = appBundleId,
                appVersion = appVersion
            )
        }
    }

    /**
     * Get a human-readable description of the device
     */
    val description: String
        get() = "$platformName $platformVersion on $deviceModel (${cpuCores} cores, ${totalMemoryMB}MB RAM)"

    /**
     * Check if device meets minimum requirements
     */
    fun meetsMinimumRequirements(): Boolean {
        return cpuCores >= 2 && totalMemoryMB >= 1024
    }
}

/**
 * Platform-specific device info collection
 */
expect fun collectDeviceInfo(): DeviceInfo
