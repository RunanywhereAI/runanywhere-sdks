package com.runanywhere.sdk.models

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.runanywhere.sdk.infrastructure.device.services.DeviceIdentity
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of device info collection.
 * Matches iOS DeviceInfo.current pattern.
 */
actual fun collectDeviceInfo(): DeviceInfo {
    val context = AndroidPlatformContext.applicationContext
    val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

    // Get memory info
    val memoryInfo = ActivityManager.MemoryInfo()
    activityManager?.getMemoryInfo(memoryInfo)
    val totalMemory = if (memoryInfo.totalMem > 0) {
        memoryInfo.totalMem
    } else {
        // Fallback for older Android versions
        Runtime.getRuntime().maxMemory()
    }

    // Determine architecture
    val architecture = when {
        Build.SUPPORTED_ABIS.any { it.contains("arm64", ignoreCase = true) } -> "arm64"
        Build.SUPPORTED_ABIS.any { it.contains("arm", ignoreCase = true) } -> "arm"
        Build.SUPPORTED_ABIS.any { it.contains("x86_64", ignoreCase = true) } -> "x86_64"
        Build.SUPPORTED_ABIS.any { it.contains("x86", ignoreCase = true) } -> "x86"
        else -> Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
    }

    // Determine device type and form factor
    val (deviceType, formFactor) = when {
        // Check if it's a tablet (simple heuristic based on screen size)
        context.resources.configuration.smallestScreenWidthDp >= 600 -> "tablet" to "tablet"
        // Default to phone
        else -> "mobile" to "phone"
    }

    // Model identifier (e.g., "Pixel 8 Pro", "SM-G998U")
    val modelIdentifier = Build.MODEL

    // User-friendly model name
    val modelName = "${Build.MANUFACTURER} ${Build.MODEL}"

    return DeviceInfo(
        deviceId = DeviceIdentity.persistentUUID,
        modelIdentifier = modelIdentifier,
        modelName = modelName,
        architecture = architecture,
        osVersion = Build.VERSION.RELEASE,
        platform = "Android",
        deviceType = deviceType,
        formFactor = formFactor,
        totalMemory = totalMemory,
        processorCount = Runtime.getRuntime().availableProcessors(),
    )
}
