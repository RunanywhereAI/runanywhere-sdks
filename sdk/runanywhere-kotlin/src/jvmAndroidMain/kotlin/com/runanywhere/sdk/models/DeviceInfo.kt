package com.runanywhere.sdk.models

import java.net.NetworkInterface
import java.security.MessageDigest
import java.util.UUID

/**
 * JVM and Android actual implementation for collecting device info.
 * Uses reflection to detect Android and call Build.* APIs when available.
 */
actual fun collectDeviceInfo(): DeviceInfo {
    return if (isAndroid()) {
        collectAndroidDeviceInfo()
    } else {
        collectJvmDeviceInfo()
    }
}

/**
 * Check if running on Android by looking at JVM properties.
 */
private fun isAndroid(): Boolean {
    val javaVmName = System.getProperty("java.vm.name") ?: ""
    val javaVendor = System.getProperty("java.vendor") ?: ""
    return javaVmName.contains("Dalvik", ignoreCase = true) ||
        javaVmName.contains("Art", ignoreCase = true) ||
        javaVendor.contains("Android", ignoreCase = true) ||
        System.getProperty("java.specification.vendor")?.contains("Android", ignoreCase = true) == true
}

/**
 * Collect device info on Android using reflection to access Build class.
 */
private fun collectAndroidDeviceInfo(): DeviceInfo {
    return try {
        val buildClass = Class.forName("android.os.Build")
        val versionClass = Class.forName("android.os.Build\$VERSION")

        val manufacturer = buildClass.getField("MANUFACTURER").get(null) as? String ?: "Unknown"
        val model = buildClass.getField("MODEL").get(null) as? String ?: "Unknown"
        val device = buildClass.getField("DEVICE").get(null) as? String ?: "Unknown"
        val brand = buildClass.getField("BRAND").get(null) as? String ?: "Unknown"

        val sdkInt = versionClass.getField("SDK_INT").get(null) as? Int ?: 0
        val release = versionClass.getField("RELEASE").get(null) as? String ?: "Unknown"

        // Get supported ABIs
        val supportedAbis =
            try {
                @Suppress("UNCHECKED_CAST")
                val abis = buildClass.getField("SUPPORTED_ABIS").get(null) as? Array<String>
                abis?.firstOrNull() ?: "unknown"
            } catch (e: Exception) {
                "unknown"
            }

        val processorCount = Runtime.getRuntime().availableProcessors()

        // Get actual physical RAM via ActivityManager (not Runtime.maxMemory() which is JVM heap limit)
        val totalMemory = getAndroidPhysicalMemory() ?: Runtime.getRuntime().maxMemory()

        DeviceInfo(
            deviceId = generateDeviceId(),
            modelIdentifier = "$manufacturer $device",
            modelName = "$brand $model",
            architecture = mapArchitecture(supportedAbis),
            osVersion = "Android $release (API $sdkInt)",
            platform = "Android",
            deviceType = "mobile",
            formFactor = "phone",
            totalMemory = totalMemory,
            processorCount = processorCount,
        )
    } catch (e: Exception) {
        // Fallback to basic JVM detection if reflection fails
        collectJvmDeviceInfo()
    }
}

/**
 * Collect device info on standard JVM.
 */
private fun collectJvmDeviceInfo(): DeviceInfo {
    val osName = System.getProperty("os.name") ?: "Unknown"
    val osVersion = System.getProperty("os.version") ?: "Unknown"
    val osArch = System.getProperty("os.arch") ?: "Unknown"

    val platform =
        when {
            osName.contains("Mac", ignoreCase = true) -> "macOS"
            osName.contains("Windows", ignoreCase = true) -> "Windows"
            osName.contains("Linux", ignoreCase = true) -> "Linux"
            else -> "JVM"
        }

    val runtime = Runtime.getRuntime()
    val totalMemory = runtime.maxMemory()
    val processorCount = runtime.availableProcessors()

    return DeviceInfo(
        deviceId = generateDeviceId(),
        modelIdentifier = osName,
        modelName = "$osName $osArch",
        architecture = mapArchitecture(osArch),
        osVersion = osVersion,
        platform = platform,
        deviceType = "desktop",
        formFactor = "desktop",
        totalMemory = totalMemory,
        processorCount = processorCount,
    )
}

/**
 * Get actual physical RAM on Android via ActivityManager reflection.
 * Runtime.maxMemory() returns the JVM heap limit (~256-512MB), not physical RAM.
 * ActivityManager.MemoryInfo.totalMem returns the real physical memory.
 */
private fun getAndroidPhysicalMemory(): Long? {
    return try {
        // Get the application context via ActivityThread reflection
        val activityThreadClass = Class.forName("android.app.ActivityThread")
        val currentAppMethod = activityThreadClass.getMethod("currentApplication")
        val context = currentAppMethod.invoke(null) ?: return null

        // Get ActivityManager service
        val contextClass = Class.forName("android.content.Context")
        val getSystemServiceMethod = contextClass.getMethod("getSystemService", String::class.java)
        val activityManager = getSystemServiceMethod.invoke(context, "activity") ?: return null

        // Create MemoryInfo and call getMemoryInfo
        val memInfoClass = Class.forName("android.app.ActivityManager\$MemoryInfo")
        val memInfo = memInfoClass.getDeclaredConstructor().newInstance()
        val getMemInfoMethod = activityManager.javaClass.getMethod("getMemoryInfo", memInfoClass)
        getMemInfoMethod.invoke(activityManager, memInfo)

        // Read totalMem field
        val totalMemField = memInfoClass.getField("totalMem")
        totalMemField.getLong(memInfo)
    } catch (e: Exception) {
        null
    }
}

/**
 * Generate a stable device ID based on hardware characteristics.
 */
private fun generateDeviceId(): String {
    return try {
        // Try to use MAC address for stable device ID (works on JVM, may fail on Android)
        val networkInterfaces = NetworkInterface.getNetworkInterfaces()
        val macAddresses =
            networkInterfaces
                ?.asSequence()
                ?.mapNotNull { it.hardwareAddress }
                ?.filter { it.isNotEmpty() }
                ?.map { it.joinToString(":") { byte -> "%02X".format(byte) } }
                ?.toList() ?: emptyList()

        if (macAddresses.isNotEmpty()) {
            val combinedMac = macAddresses.sorted().joinToString("-")
            hashString(combinedMac)
        } else {
            // Fallback to system properties
            val systemInfo =
                listOf(
                    System.getProperty("os.name"),
                    System.getProperty("os.arch"),
                    System.getProperty("user.name"),
                    System.getProperty("user.home"),
                ).filterNotNull().joinToString("-")
            if (systemInfo.isNotEmpty()) {
                hashString(systemInfo)
            } else {
                UUID.randomUUID().toString()
            }
        }
    } catch (e: Exception) {
        // Ultimate fallback - random UUID (not stable across restarts)
        UUID.randomUUID().toString()
    }
}

/**
 * Hash a string to create a device ID.
 */
private fun hashString(input: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val hash = digest.digest(input.toByteArray())
    return hash.take(16).joinToString("") { "%02x".format(it) }
}

/**
 * Map architecture names to standard names.
 */
private fun mapArchitecture(osArch: String): String {
    return when {
        osArch.contains("arm64", ignoreCase = true) -> "arm64"
        osArch.contains("aarch64", ignoreCase = true) -> "arm64"
        osArch.contains("arm", ignoreCase = true) -> "arm"
        osArch.contains("x86_64", ignoreCase = true) -> "x86_64"
        osArch.contains("amd64", ignoreCase = true) -> "x86_64"
        osArch.contains("64", ignoreCase = true) -> "x86_64"
        osArch.contains("x86", ignoreCase = true) -> "x86"
        osArch.contains("86", ignoreCase = true) -> "x86"
        else -> osArch
    }
}
