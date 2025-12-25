package com.runanywhere.sdk.models

import com.runanywhere.sdk.infrastructure.device.services.DeviceIdentity

/**
 * JVM implementation of device info collection.
 * Matches iOS DeviceInfo.current pattern.
 */
actual fun collectDeviceInfo(): DeviceInfo {
    val runtime = Runtime.getRuntime()
    val osArch = System.getProperty("os.arch") ?: "unknown"
    val osName = System.getProperty("os.name") ?: "Unknown"
    val osVersion = System.getProperty("os.version") ?: "Unknown"

    // Determine architecture
    val architecture =
        when {
            osArch.contains("aarch64", ignoreCase = true) -> "arm64"
            osArch.contains("arm", ignoreCase = true) -> "arm"
            osArch.contains("64", ignoreCase = true) -> "x86_64"
            else -> osArch
        }

    // Determine platform and form factor
    val (platform, deviceType, formFactor) =
        when {
            osName.contains("Mac", ignoreCase = true) -> Triple("macOS", "desktop", if (osArch.contains("arm")) "laptop" else "desktop")
            osName.contains("Windows", ignoreCase = true) -> Triple("Windows", "desktop", "desktop")
            osName.contains("Linux", ignoreCase = true) -> Triple("Linux", "desktop", "desktop")
            else -> Triple("JVM", "desktop", "desktop")
        }

    // Model identifier (e.g., "x86_64 macOS" or "aarch64 Linux")
    val modelIdentifier = "$osArch $osName"

    // User-friendly model name
    val modelName =
        when {
            osName.contains("Mac", ignoreCase = true) -> "Mac ($architecture)"
            osName.contains("Windows", ignoreCase = true) -> "Windows PC"
            osName.contains("Linux", ignoreCase = true) -> "Linux ($architecture)"
            else -> "JVM ($osArch)"
        }

    return DeviceInfo(
        deviceId = DeviceIdentity.persistentUUID,
        modelIdentifier = modelIdentifier,
        modelName = modelName,
        architecture = architecture,
        osVersion = osVersion,
        platform = platform,
        deviceType = deviceType,
        formFactor = formFactor,
        totalMemory = runtime.maxMemory(),
        processorCount = runtime.availableProcessors(),
    )
}
