package com.runanywhere.sdk.services.deviceinfo

import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.models.GPUType
import java.net.InetAddress
import java.security.MessageDigest

/**
 * JVM implementation of platform-specific device information collection
 */
actual suspend fun collectPlatformDeviceInfo(): DeviceInfoData {
    val runtime = Runtime.getRuntime()
    val totalMemoryMB = (runtime.maxMemory() / (1024 * 1024))
    val availableMemoryMB = ((runtime.maxMemory() - runtime.totalMemory() + runtime.freeMemory()) / (1024 * 1024))

    return DeviceInfoData(
        deviceId = generateJvmDeviceId(),
        deviceName = InetAddress.getLocalHost().hostName,
        systemName = System.getProperty("os.name", "Unknown"),
        systemVersion = System.getProperty("os.version", "Unknown"),
        modelName = "JVM",
        modelIdentifier = System.getProperty("java.vm.name", "Unknown JVM"),
        cpuType = System.getProperty("os.arch", "Unknown"),
        cpuArchitecture = System.getProperty("os.arch", "Unknown"),
        cpuCoreCount = runtime.availableProcessors(),
        totalMemoryMB = totalMemoryMB,
        availableMemoryMB = availableMemoryMB,
        totalStorageMB = 0, // Not easily accessible in JVM
        availableStorageMB = 0, // Not easily accessible in JVM
        gpuType = GPUType.UNKNOWN,
        batteryLevel = null, // Not applicable for JVM
        memoryPressure = 0.0f,
        benchmarkScore = calculateJvmCapabilityScore(runtime.availableProcessors(), totalMemoryMB.toInt()),
        updatedAt = System.currentTimeMillis()
    )
}

private fun generateJvmDeviceId(): String {
    return try {
        val identifier = buildString {
            append(System.getProperty("user.name", ""))
            append(System.getProperty("os.name", ""))
            append(System.getProperty("os.arch", ""))
            append(System.getProperty("java.vm.name", ""))
            try {
                append(InetAddress.getLocalHost().hostName)
            } catch (e: Exception) {
                append("localhost")
            }
        }

        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(identifier.toByteArray())
        "jvm-" + hash.take(8).joinToString("") { "%02x".format(it) }
    } catch (e: Exception) {
        "jvm-${System.currentTimeMillis().toString(16)}"
    }
}

private fun calculateJvmCapabilityScore(cores: Int, memoryMB: Int): Int {
    var score = 50 // Base score for JVM

    // Add points for CPU cores
    score += when {
        cores >= 16 -> 20
        cores >= 8 -> 15
        cores >= 4 -> 10
        else -> 5
    }

    // Add points for memory
    score += when {
        memoryMB >= 16384 -> 20
        memoryMB >= 8192 -> 15
        memoryMB >= 4096 -> 10
        else -> 5
    }

    return score.coerceIn(0, 100)
}
