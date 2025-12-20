package com.runanywhere.sdk.models

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of device info collection
 */
actual fun collectDeviceInfo(): DeviceInfo {
    val context = AndroidPlatformContext.applicationContext
    val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

    // Get memory info
    val memoryInfo = ActivityManager.MemoryInfo()
    activityManager?.getMemoryInfo(memoryInfo)
    val totalMemoryMB =
        if (memoryInfo.totalMem > 0) {
            memoryInfo.totalMem / (1024 * 1024)
        } else {
            // Fallback for older Android versions
            Runtime.getRuntime().maxMemory() / (1024 * 1024)
        }

    // Get app info
    val packageManager = context.packageManager
    val packageInfo =
        try {
            packageManager.getPackageInfo(context.packageName, 0)
        } catch (e: Exception) {
            null
        }

    return DeviceInfo.create(
        platformName = "Android",
        platformVersion = "API ${Build.VERSION.SDK_INT}",
        deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}",
        osVersion = "Android ${Build.VERSION.RELEASE}",
        sdkVersion = "0.1.0",
        cpuCores = Runtime.getRuntime().availableProcessors(),
        totalMemoryMB = totalMemoryMB,
        appBundleId = context.packageName,
        appVersion =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo?.versionName
            } else {
                @Suppress("DEPRECATION")
                packageInfo?.versionName
            },
    )
}
