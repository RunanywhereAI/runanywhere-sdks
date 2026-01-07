package com.runanywhere.sdk.utils

import java.net.InetAddress
import java.util.*
import java.util.prefs.Preferences

/**
 * JVM implementation of platform utilities
 */
actual object PlatformUtils {
    private val prefs = Preferences.userNodeForPackage(PlatformUtils::class.java)
    private const val DEVICE_ID_KEY = "com.runanywhere.sdk.deviceId"

    actual fun getDeviceId(): String {
        // Check if we already have a stored device ID
        var deviceId = prefs.get(DEVICE_ID_KEY, null)

        if (deviceId == null) {
            // Generate a new UUID and store it
            deviceId = UUID.randomUUID().toString()
            prefs.put(DEVICE_ID_KEY, deviceId)
            prefs.flush()
        }

        return deviceId
    }

    actual fun getPlatformName(): String {
        // Return the actual OS platform that the backend expects
        val osName = System.getProperty("os.name", "").lowercase()
        return when {
            osName.contains("mac") || osName.contains("darwin") -> "macos"
            osName.contains("win") -> "windows"
            osName.contains("nix") || osName.contains("nux") || osName.contains("aix") -> "linux"
            else -> "linux" // Default to linux for other Unix-like systems
        }
    }

    actual fun getDeviceInfo(): Map<String, String> =
        mapOf(
            "platform" to getPlatformName(),
            "os_name" to System.getProperty("os.name", "Unknown"),
            "os_version" to getOSVersion(),
            "os_arch" to System.getProperty("os.arch", "Unknown"),
            "java_version" to System.getProperty("java.version", "Unknown"),
            "java_vendor" to System.getProperty("java.vendor", "Unknown"),
            "user_country" to System.getProperty("user.country", "Unknown"),
            "user_language" to System.getProperty("user.language", "Unknown"),
            "hostname" to getHostName(),
            "device_model" to getDeviceModel(),
        )

    actual fun getOSVersion(): String = System.getProperty("os.version", "Unknown")

    actual fun getDeviceModel(): String {
        // For JVM, return the OS name and architecture
        val osName = System.getProperty("os.name", "Unknown")
        val osArch = System.getProperty("os.arch", "Unknown")
        return "$osName $osArch"
    }

    actual fun getAppVersion(): String? {
        // Try to get version from manifest or return null
        return try {
            PlatformUtils::class.java.`package`?.implementationVersion
        } catch (e: Exception) {
            null
        }
    }

    private fun getHostName(): String =
        try {
            InetAddress.getLocalHost().hostName
        } catch (e: Exception) {
            "Unknown"
        }
}
