package com.runanywhere.sdk.utils

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import java.util.*

/**
 * Android implementation of platform utilities
 */
actual object PlatformUtils {

    internal lateinit var applicationContext: Context
    private const val PREFS_NAME = "com.runanywhere.sdk.prefs"
    private const val DEVICE_ID_KEY = "device_id"

    /**
     * Initialize with application context
     */
    fun init(context: Context) {
        applicationContext = context.applicationContext
    }

    @SuppressLint("HardwareIds")
    actual fun getDeviceId(): String {
        if (!::applicationContext.isInitialized) {
            // Fallback to random UUID if context not initialized
            return UUID.randomUUID().toString()
        }

        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Check if we have a stored device ID
        var deviceId = prefs.getString(DEVICE_ID_KEY, null)

        if (deviceId == null) {
            // Try to get Android ID
            deviceId = try {
                Settings.Secure.getString(
                    applicationContext.contentResolver,
                    Settings.Secure.ANDROID_ID
                )
            } catch (e: Exception) {
                null
            }

            // Fallback to UUID if Android ID is not available
            if (deviceId.isNullOrEmpty() || deviceId == "9774d56d682e549c") {
                deviceId = UUID.randomUUID().toString()
            }

            // Store for future use
            prefs.edit().putString(DEVICE_ID_KEY, deviceId).apply()
        }

        return deviceId
    }

    actual fun getPlatformName(): String {
        return "android"
    }

    actual fun getDeviceInfo(): Map<String, String> {
        return mapOf(
            "platform" to getPlatformName(),
            "os_version" to getOSVersion(),
            "api_level" to Build.VERSION.SDK_INT.toString(),
            "device_manufacturer" to Build.MANUFACTURER,
            "device_model" to getDeviceModel(),
            "device_brand" to Build.BRAND,
            "device_product" to Build.PRODUCT,
            "device_hardware" to Build.HARDWARE,
            "device_board" to Build.BOARD,
            "device_display" to Build.DISPLAY,
            "device_fingerprint" to Build.FINGERPRINT,
            "supported_abis" to Build.SUPPORTED_ABIS.joinToString(",")
        )
    }

    actual fun getOSVersion(): String {
        return "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
    }

    actual fun getDeviceModel(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }

    actual fun getAppVersion(): String? {
        if (!::applicationContext.isInitialized) {
            return null
        }

        return try {
            val packageInfo = applicationContext.packageManager
                .getPackageInfo(applicationContext.packageName, 0)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toString()
            } + " (${packageInfo.versionName})"
        } catch (e: Exception) {
            null
        }
    }
}
