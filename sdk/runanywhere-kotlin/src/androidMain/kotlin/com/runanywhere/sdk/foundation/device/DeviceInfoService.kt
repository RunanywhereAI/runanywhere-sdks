package com.runanywhere.sdk.foundation.device

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of DeviceInfoService
 *
 * Collects device information using Android APIs
 */
actual class DeviceInfoService {
    private val context: Context? by lazy {
        if (AndroidPlatformContext.isInitialized()) {
            AndroidPlatformContext.applicationContext
        } else {
            null
        }
    }

    actual fun getOSName(): String = "Android"

    actual fun getOSVersion(): String = Build.VERSION.RELEASE

    actual fun getDeviceModel(): String {
        val manufacturer = Build.MANUFACTURER
        val model = Build.MODEL
        return if (model.startsWith(manufacturer, ignoreCase = true)) {
            model.replaceFirstChar { it.uppercase() }
        } else {
            "${manufacturer.replaceFirstChar { it.uppercase() }} $model"
        }
    }

    actual fun getChipName(): String? =
        try {
            // Get primary ABI (architecture)
            val abis = Build.SUPPORTED_ABIS
            if (abis.isNotEmpty()) {
                abis[0]
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }

    actual fun getTotalMemoryGB(): Double? {
        return try {
            val ctx = context ?: return null
            val activityManager =
                ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    ?: return null

            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)

            // Convert bytes to GB
            memInfo.totalMem / (1024.0 * 1024.0 * 1024.0)
        } catch (e: Exception) {
            null
        }
    }

    actual fun getTotalMemoryBytes(): Long? {
        return try {
            val ctx = context ?: return null
            val activityManager =
                ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    ?: return null

            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)

            // Return bytes directly (matching iOS)
            memInfo.totalMem
        } catch (e: Exception) {
            null
        }
    }

    actual fun getArchitecture(): String? =
        try {
            // Get primary ABI (architecture) - same as chip name for Android
            val abis = Build.SUPPORTED_ABIS
            if (abis.isNotEmpty()) {
                abis[0]
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
}
