package com.runanywhere.sdk.models

import kotlinx.cinterop.*
import platform.posix.*

/**
 * Native implementation of device info collection
 */
actual fun collectDeviceInfo(): DeviceInfo {
    // Get system info using POSIX calls
    val platformName = when {
        Platform.osFamily == OsFamily.MACOS -> "macOS"
        Platform.osFamily == OsFamily.LINUX -> "Linux"
        Platform.osFamily == OsFamily.WINDOWS -> "Windows"
        else -> "Native"
    }

    // Get CPU core count
    val cpuCores = try {
        memScoped {
            val result = alloc<IntVar>()
            val size = alloc<size_tVar>()
            size.value = sizeOf<IntVar>().convert()

            // Try to get CPU core count (platform-specific)
            when (Platform.osFamily) {
                OsFamily.MACOS, OsFamily.LINUX -> {
                    if (sysctlbyname("hw.ncpu", result.ptr, size.ptr, null, 0u) == 0) {
                        result.value
                    } else {
                        1 // Fallback
                    }
                }
                else -> 1 // Fallback for other platforms
            }
        }
    } catch (e: Exception) {
        1 // Fallback if system call fails
    }

    // Estimate memory (simplified for native)
    val totalMemoryMB = try {
        when (Platform.osFamily) {
            OsFamily.MACOS, OsFamily.LINUX -> {
                // Try to read from /proc/meminfo on Linux or use sysctl on macOS
                // For now, use a reasonable default
                2048L
            }
            else -> 1024L // Default for other platforms
        }
    } catch (e: Exception) {
        1024L
    }

    return DeviceInfo.create(
        platformName = platformName,
        platformVersion = Platform.osFamily.name,
        deviceModel = "${Platform.cpuArchitecture.name} Native",
        osVersion = "Native",
        sdkVersion = "0.1.0",
        cpuCores = cpuCores,
        totalMemoryMB = totalMemoryMB,
        appBundleId = null,
        appVersion = null
    )
}

// Helper function declaration for sysctl (not all platforms may have this)
@OptIn(ExperimentalForeignApi::class)
private external fun sysctlbyname(name: String, oldp: COpaquePointer?, oldlenp: CPointer<size_tVar>?, newp: COpaquePointer?, newlen: size_t): Int
