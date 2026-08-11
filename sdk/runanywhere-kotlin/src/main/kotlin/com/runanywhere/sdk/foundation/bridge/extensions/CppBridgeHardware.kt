/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Hardware extension for CppBridge.
 *
 * Mirrors Swift CppBridge+Hardware.swift. Wraps `rac_hardware_profile_*` JNI
 * thunks (currently only `racHardwareProfileGet`) and consolidates the
 * platform-side hardware fallback helpers (architecture / total memory /
 * chip name / GPU family) used when populating device registration payloads.
 *
 * The fallback helpers are duplicated here from CppBridgeDevice.kt as part of
 * task B16 — CppBridgeDevice keeps its copy intact until the follow-up
 * cleanup task migrates its call sites to this object.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Hardware profile bridge wrapping the `rac_hardware_profile_*` ABI.
 *
 * The C++ implementation (`rac_hardware_abi.cpp`) is the source of truth for
 * chip / accelerator / NPU detection on Android (it reads
 * `ro.hardware.chipname` / `ro.board.platform` via `__system_property_get`).
 * This object exposes the canonical proto-byte path that the public
 * `RunAnywhere.hardware` namespace consumes.
 *
 * The fallback helpers ([defaultArchitecture], [defaultTotalMemory],
 * [defaultChipName], [defaultGpuFamily]) are kept here as a single home for
 * "CPU info / RAM detection / NPU detection / accelerator queries" so device
 * registration callbacks no longer have to inline reflection into Build.* and
 * /proc paths themselves.
 *
 * Mirrors:
 *  - Swift `CppBridge+Hardware.swift` (`CppBridge.Hardware.getProfile()` etc.)
 */
object CppBridgeHardware {
    private const val TAG = "CppBridgeHardware"

    // Platform fallbacks (CPU / RAM / NPU / GPU)
    //
    // These helpers run on Android via reflection so the SDK keeps building
    // on plain JVM. They are only consulted when the optional
    // [CppBridgeDevice.DeviceInfoProvider] is not set; the C++ hardware ABI
    // is still preferred wherever it returns data.

    /**
     * Get default architecture from system properties.
     *
     * On Android, uses `Build.SUPPORTED_ABIS` to get the actual ABI string.
     * Returns actual Android ABI: "arm64-v8a", "armeabi-v7a", "x86_64",
     * "x86", etc. Backend accepts: arm64, arm64-v8a, armeabi-v7a, x86_64,
     * x86, unknown.
     */
    fun defaultArchitecture(): String {
        // Try to get Android SUPPORTED_ABIS first (returns "arm64-v8a", "armeabi-v7a", etc.)
        try {
            val buildClass = Class.forName("android.os.Build")

            @Suppress("UNCHECKED_CAST")
            val supportedAbis = buildClass.getField("SUPPORTED_ABIS").get(null) as? Array<String>
            if (!supportedAbis.isNullOrEmpty()) {
                return supportedAbis[0] // Return the primary ABI as-is
            }
        } catch (e: Exception) {
            // Fall through to system property
        }

        // Fallback: map JVM os.arch to Android-style ABI strings
        val arch = System.getProperty("os.arch") ?: return "unknown"
        return when {
            arch.contains("aarch64", ignoreCase = true) -> "arm64-v8a"
            arch.contains("arm64", ignoreCase = true) -> "arm64-v8a"
            arch.contains("arm", ignoreCase = true) -> "armeabi-v7a"
            arch.contains("x86_64", ignoreCase = true) -> "x86_64"
            arch.contains("amd64", ignoreCase = true) -> "x86_64"
            arch.contains("x86", ignoreCase = true) -> "x86"
            else -> "unknown"
        }
    }

    /**
     * Get default total memory from system.
     *
     * On Android, uses ActivityManager to get actual device RAM.
     * Falls back to /proc/meminfo via [com.runanywhere.sdk.infrastructure.device.models.domain.PhysicalMemoryProbe].
     *
     * G-DV20: Never trust `Runtime.maxMemory()` alone on Android — it returns
     * the JVM heap cap (~512 MB), not physical RAM.
     */
    fun defaultTotalMemory(): Long {
        // Try to get actual device memory via ActivityManager
        try {
            val contextClass = Class.forName("android.content.Context")
            val activityServiceField = contextClass.getField("ACTIVITY_SERVICE")
            val activityService = activityServiceField.get(null) as String

            // Get application context
            val activityThreadClass = Class.forName("android.app.ActivityThread")
            val currentAppMethod = activityThreadClass.getMethod("currentApplication")
            val context = currentAppMethod.invoke(null)

            if (context != null) {
                val getSystemServiceMethod = contextClass.getMethod("getSystemService", String::class.java)
                val activityManager = getSystemServiceMethod.invoke(context, activityService)

                if (activityManager != null) {
                    val memInfoClass = Class.forName("android.app.ActivityManager\$MemoryInfo")
                    val memInfo = memInfoClass.getDeclaredConstructor().newInstance()

                    val getMemInfoMethod = activityManager.javaClass.getMethod("getMemoryInfo", memInfoClass)
                    getMemInfoMethod.invoke(activityManager, memInfo)

                    val totalMemField = memInfoClass.getField("totalMem")
                    return totalMemField.getLong(memInfo)
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Could not get device memory via ActivityManager: ${e.message}",
            )
        }

        // Fallback: parse /proc/meminfo, then Runtime.maxMemory() as last resort.
        return com.runanywhere.sdk.infrastructure.device.models.domain.PhysicalMemoryProbe
            .totalPhysicalMemoryBytes()
    }

    /**
     * Resolve chip name via `rac_device_resolve_chip_name`.
     *
     * Platforms gather OS-readable candidates (SOC_MODEL / HARDWARE /
     * /proc/cpuinfo); commons owns the four-tier policy.
     */
    fun defaultChipName(architecture: String): String {
        var socManufacturer: String? = null
        var socModel: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                socModel =
                    Build.SOC_MODEL.takeIf {
                        it.isNotBlank() && !it.equals(Build.UNKNOWN, ignoreCase = true)
                    }
                socManufacturer =
                    Build.SOC_MANUFACTURER.takeIf {
                        it.isNotBlank() && !it.equals(Build.UNKNOWN, ignoreCase = true)
                    }
            } catch (_: Exception) {
                // Fall through with nulls
            }
        }
        val buildHardware =
            try {
                Build.HARDWARE.takeIf { !it.isNullOrEmpty() && it != "unknown" }
            } catch (_: Exception) {
                null
            }
        val cpuinfoHardware =
            try {
                java.io.File("/proc/cpuinfo")
                    .readText()
                    .lines()
                    .find { it.startsWith("Hardware", ignoreCase = true) }
                    ?.substringAfter(":")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
            } catch (_: Exception) {
                null
            }
        return RunAnywhereBridge.racDeviceResolveChipName(
            socManufacturer,
            socModel,
            buildHardware,
            cpuinfoHardware,
            architecture,
        )
    }

    /**
     * Classify GPU family via `rac_device_classify_gpu_family`.
     */
    fun defaultGpuFamily(chipName: String): String {
        var socManufacturer: String? = null
        var socModel: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                socManufacturer = Build.SOC_MANUFACTURER
                socModel = Build.SOC_MODEL
            } catch (_: Exception) {
                // Fall through
            }
        }
        return RunAnywhereBridge.racDeviceClassifyGpuFamily(socManufacturer, socModel, chipName)
    }

    /**
     * Available RAM coalesce via `rac_device_coalesce_available_memory`.
     *
     * Platforms probe ActivityManager / MemAvailable; commons maps non-positive
     * probes to 0 (UNKNOWN) and never invents total/2.
     */
    fun defaultAvailableMemory(@Suppress("UNUSED_PARAMETER") totalMemory: Long): Long {
        var probed = 0L
        try {
            val context =
                if (AndroidPlatformContext.isInitialized()) {
                    AndroidPlatformContext.applicationContext
                } else {
                    null
                }
            val activityManager = context?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (activityManager != null) {
                val memInfo = ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(memInfo)
                if (memInfo.availMem > 0) {
                    probed = memInfo.availMem
                }
            }
        } catch (_: Exception) {
            // Fall through to /proc/meminfo
        }

        if (probed <= 0L) {
            try {
                java.io.File("/proc/meminfo").useLines { lines ->
                    val memAvailable = lines.find { it.startsWith("MemAvailable:") }
                    val kb =
                        memAvailable
                            ?.substringAfter(":")
                            ?.trim()
                            ?.removeSuffix(" kB")
                            ?.trim()
                            ?.toLongOrNull()
                    if (kb != null && kb > 0) {
                        probed = kb * 1024L
                    }
                }
            } catch (_: Exception) {
                // Fall through
            }
        }

        return RunAnywhereBridge.racDeviceCoalesceAvailableMemory(probed)
    }

    /**
     * NPU presence via `rac_device_heuristic_has_npu`.
     */
    fun defaultHasNeuralEngine(chipName: String): Boolean {
        var socManufacturer: String? = null
        var socModel: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                socManufacturer = Build.SOC_MANUFACTURER
                socModel = Build.SOC_MODEL
            } catch (_: Exception) {
                // Fall through
            }
        }
        return RunAnywhereBridge.racDeviceHeuristicHasNpu(socManufacturer, socModel, chipName)
    }

    /**
     * P/E core split via `rac_device_split_performance_cores`.
     *
     * Platforms read sysfs `cpuinfo_max_freq`; commons owns the max-frequency
     * split policy (UNKNOWN = 0/0 when samples are incomplete).
     */
    fun defaultCoreSplit(coreCount: Int): Pair<Int, Int> {
        if (coreCount <= 0) {
            val split = RunAnywhereBridge.racDeviceSplitPerformanceCores(null)
            return split[0] to split[1]
        }
        val freqs =
            LongArray(coreCount) { cpu ->
                try {
                    val sysfs = java.io.File("/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq")
                    sysfs.readText().trim().toLongOrNull() ?: 0L
                } catch (_: Exception) {
                    0L
                }
            }
        val split = RunAnywhereBridge.racDeviceSplitPerformanceCores(freqs)
        return split[0] to split[1]
    }
}
