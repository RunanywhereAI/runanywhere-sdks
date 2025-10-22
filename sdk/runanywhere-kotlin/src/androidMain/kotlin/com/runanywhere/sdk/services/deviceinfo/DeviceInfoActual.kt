package com.runanywhere.sdk.services.deviceinfo

import android.os.Build
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.ThermalState

/**
 * Android implementation of platform-specific device information collection
 */
actual suspend fun collectPlatformDeviceInfo(): DeviceInfoData {
    // For now, we need to get context from somewhere. This is a simplified implementation
    // that creates basic device info without context dependencies

    return DeviceInfoData(
        deviceId = "android-${Build.FINGERPRINT.hashCode()}",
        deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
        systemName = "Android",
        systemVersion = Build.VERSION.RELEASE,
        modelName = Build.MODEL,
        modelIdentifier = Build.DEVICE,

        // CPU information
        cpuType = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown",
        cpuArchitecture = when {
            Build.SUPPORTED_ABIS.any { it.startsWith("arm64") } -> "arm64"
            Build.SUPPORTED_ABIS.any { it.startsWith("arm") } -> "arm"
            Build.SUPPORTED_ABIS.any { it.startsWith("x86_64") } -> "x86_64"
            Build.SUPPORTED_ABIS.any { it.startsWith("x86") } -> "x86"
            else -> "unknown"
        },
        cpuCoreCount = Runtime.getRuntime().availableProcessors(),
        cpuFrequencyMHz = null,

        // Memory information (basic without context)
        totalMemoryMB = 0,
        availableMemoryMB = 0,

        // Storage information (basic without context)
        totalStorageMB = 0,
        availableStorageMB = 0,

        // GPU information
        gpuType = GPUType.UNKNOWN,
        gpuName = null,
        gpuVendor = null,
        supportsMetal = false,
        supportsVulkan = Build.VERSION.SDK_INT >= 24,
        supportsOpenCL = false,

        // Battery information (basic)
        batteryLevel = null,
        batteryState = BatteryState.UNKNOWN,
        thermalState = ThermalState.NOMINAL,
        isLowPowerMode = false,

        // Connectivity (basic assumptions)
        hasCellular = true,
        hasWifi = true,
        hasBluetooth = true,

        // Capabilities (basic assumptions)
        hasCamera = true,
        hasMicrophone = true,
        hasSpeakers = true,
        hasBiometric = false,

        // Performance
        benchmarkScore = null,
        memoryPressure = 0.0f,

        updatedAt = System.currentTimeMillis()
    )
}
