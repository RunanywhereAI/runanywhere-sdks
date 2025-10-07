package com.runanywhere.sdk.foundation

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import java.security.MessageDigest

/**
 * Android-specific implementations for PersistentDeviceIdentity
 * Uses Android system APIs to gather device information
 */

// Get the Android context from the platform context
private fun getAndroidContext(): Context? {
    return try {
        // This will be provided by the Android platform setup
        com.runanywhere.sdk.foundation.getAndroidApplicationContext()
    } catch (e: Exception) {
        null
    }
}

/**
 * Get platform vendor UUID - uses Android ID when available
 */
@SuppressLint("HardwareIds")
actual suspend fun getPlatformVendorUUID(): String? {
    return try {
        val context = getAndroidContext() ?: return null

        // Use Android ID as vendor UUID
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID
        )

        if (androidId != null && androidId != "9774d56d682e549c") { // Default emulator ID
            // Format as UUID
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(androidId.toByteArray())

            // Format first 16 bytes as UUID
            val bytes = hash.take(16).toByteArray()
            bytes[6] = (bytes[6].toInt() and 0x0f or 0x40).toByte() // Version 4
            bytes[8] = (bytes[8].toInt() and 0x3f or 0x80).toByte() // Variant bits

            "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x".format(
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5],
                bytes[6], bytes[7],
                bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        } else {
            null
        }
    } catch (e: Exception) {
        null
    }
}

/**
 * Get comprehensive platform device information for fingerprinting
 */
actual fun getPlatformDeviceInfo(): PlatformDeviceInfo {
    val runtime = Runtime.getRuntime()

    // Get total memory
    val totalMemory = runtime.maxMemory()

    // Get architecture
    val architecture = when {
        Build.SUPPORTED_64_BIT_ABIS.isNotEmpty() -> "arm64"
        Build.SUPPORTED_32_BIT_ABIS.isNotEmpty() -> "arm32"
        else -> Build.CPU_ABI ?: "unknown"
    }

    // Get core count
    val coreCount = runtime.availableProcessors()

    // Get device model
    val deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim()

    // Get OS major version
    val osMajorVersion = Build.VERSION.SDK_INT.toString()

    return PlatformDeviceInfo(
        totalMemory = totalMemory,
        architecture = architecture,
        coreCount = coreCount,
        deviceModel = deviceModel,
        osMajorVersion = osMajorVersion
    )
}

/**
 * Platform-specific SHA256 implementation
 */
actual fun platformSha256(input: String): String {
    return try {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(input.toByteArray(Charsets.UTF_8))
        hash.joinToString("") { "%02x".format(it) }
    } catch (e: Exception) {
        // Fallback to hashCode if SHA256 is not available
        input.hashCode().toString(16)
    }
}

/**
 * Extended Android device information collector
 * Provides comprehensive system information for device registration
 */
object AndroidDeviceInfoCollector {

    /**
     * Collect comprehensive device information for registration
     */
    fun collectDeviceInfo(): Map<String, Any> {
        val info = mutableMapOf<String, Any>()
        val runtime = Runtime.getRuntime()

        try {
            // Basic system information
            info["platform"] = "Android"
            info["os_name"] = "Android"
            info["os_version"] = Build.VERSION.RELEASE
            info["sdk_int"] = Build.VERSION.SDK_INT
            info["security_patch"] = Build.VERSION.SECURITY_PATCH

            // Device information
            info["manufacturer"] = Build.MANUFACTURER
            info["brand"] = Build.BRAND
            info["model"] = Build.MODEL
            info["device"] = Build.DEVICE
            info["product"] = Build.PRODUCT
            info["board"] = Build.BOARD
            info["hardware"] = Build.HARDWARE

            // Architecture information
            info["supported_abis"] = Build.SUPPORTED_ABIS.toList()
            info["supported_32_bit_abis"] = Build.SUPPORTED_32_BIT_ABIS.toList()
            info["supported_64_bit_abis"] = Build.SUPPORTED_64_BIT_ABIS.toList()

            // Hardware information
            info["processor_count"] = runtime.availableProcessors()
            info["max_memory"] = runtime.maxMemory()
            info["total_memory"] = runtime.totalMemory()
            info["free_memory"] = runtime.freeMemory()

            // Build information
            info["build_id"] = Build.ID
            info["build_type"] = Build.TYPE
            info["build_tags"] = Build.TAGS
            info["build_time"] = Build.TIME

            // Radio version if available
            try {
                info["radio_version"] = Build.getRadioVersion()
            } catch (e: Exception) {
                // Not available on all devices
            }

            // Additional hardware details
            info["cpu_abi"] = Build.CPU_ABI
            if (Build.CPU_ABI2.isNotEmpty()) {
                info["cpu_abi2"] = Build.CPU_ABI2
            }

            // Bootloader and fingerprint
            info["bootloader"] = Build.BOOTLOADER
            info["fingerprint"] = Build.FINGERPRINT

        } catch (e: Exception) {
            info["collection_error"] = e.message ?: "Unknown error"
        }

        return info
    }

    /**
     * Get device capabilities assessment
     */
    fun getDeviceCapabilities(): Map<String, Any> {
        val capabilities = mutableMapOf<String, Any>()
        val runtime = Runtime.getRuntime()

        try {
            val maxMemoryMB = runtime.maxMemory() / (1024 * 1024)
            val processors = runtime.availableProcessors()
            val sdkInt = Build.VERSION.SDK_INT

            // Memory capability
            capabilities["memory_tier"] = when {
                maxMemoryMB >= 8192 -> "high"     // 8GB+
                maxMemoryMB >= 6144 -> "medium"   // 6GB+
                maxMemoryMB >= 4096 -> "low"      // 4GB+
                else -> "minimal"                 // < 4GB
            }

            // CPU capability
            capabilities["cpu_tier"] = when {
                processors >= 8 -> "high"        // 8+ cores
                processors >= 6 -> "medium"      // 6+ cores
                processors >= 4 -> "low"         // 4+ cores
                else -> "minimal"                 // < 4 cores
            }

            // OS capability
            capabilities["os_tier"] = when {
                sdkInt >= 33 -> "high"           // Android 13+
                sdkInt >= 30 -> "medium"         // Android 11+
                sdkInt >= 26 -> "low"            // Android 8+
                else -> "minimal"                // < Android 8
            }

            // Overall capability score (0-100)
            var score = 0
            score += when {
                maxMemoryMB >= 8192 -> 35
                maxMemoryMB >= 6144 -> 25
                maxMemoryMB >= 4096 -> 15
                else -> 5
            }
            score += when {
                processors >= 8 -> 25
                processors >= 6 -> 20
                processors >= 4 -> 15
                else -> 5
            }
            score += when {
                sdkInt >= 33 -> 20
                sdkInt >= 30 -> 15
                sdkInt >= 26 -> 10
                else -> 5
            }
            // Add bonus for 64-bit support
            if (Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()) {
                score += 15
            }

            capabilities["capability_score"] = minOf(score, 100)
            capabilities["recommended_models"] = when {
                score >= 80 -> listOf("medium", "small", "tiny")
                score >= 60 -> listOf("small", "tiny")
                score >= 40 -> listOf("tiny")
                else -> listOf("tiny")
            }

        } catch (e: Exception) {
            capabilities["error"] = e.message ?: "Unknown error"
        }

        return capabilities
    }
}

/**
 * Function to get Android application context
 * Uses the existing AndroidPlatformContext
 */
private fun getAndroidApplicationContext(): Context {
    return com.runanywhere.sdk.storage.AndroidPlatformContext.applicationContext
}
