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

import ai.runanywhere.proto.v1.AccelerationPreference
import ai.runanywhere.proto.v1.AcceleratorInfo
import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.foundation.errors.SDKException
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

    /**
     * Retrieve the full hardware profile.
     *
     * Returns the decoded [HardwareProfileResult] from the native
     * `rac_hardware_profile_get` thunk, or an empty default if the C++
     * implementation has not yet populated the profile.
     */
    fun getProfile(): HardwareProfileResult {
        val bytes = RunAnywhereBridge.racHardwareProfileGet()
        return if (bytes != null && bytes.isNotEmpty()) {
            HardwareProfileResult.ADAPTER.decode(bytes)
        } else {
            HardwareProfileResult()
        }
    }

    /**
     * Decode the lightweight accelerator-only `HardwareProfileResult` returned
     * by `rac_hardware_get_accelerators` and surface just its `accelerators`
     * list. Mirrors Swift `CppBridge.Hardware.getAccelerators()`. Returns an
     * empty list when the commons ABI returns null/empty (matches Swift's
     * empty-`accelerators` result when the symbol is missing).
     */
    fun getAccelerators(): List<AcceleratorInfo> {
        val bytes = RunAnywhereBridge.racHardwareGetAccelerators()
        return if (bytes != null && bytes.isNotEmpty()) {
            HardwareProfileResult.ADAPTER.decode(bytes).accelerators
        } else {
            emptyList()
        }
    }

    /**
     * Set the preferred accelerator for subsequent routing / inference calls.
     * Mirrors Swift `CppBridge.Hardware.setAcceleratorPreference(_:)`: throws
     * `SDKException` when the commons ABI returns a non-success `rac_result_t`.
     */
    fun setAcceleratorPreference(pref: AccelerationPreference) {
        val rc =
            RunAnywhereBridge.racHardwareSetAcceleratorPreference(
                AccelerationPreference.ADAPTER.encode(pref),
            )
        if (rc != 0) {
            throw SDKException.operation(
                "Failed to set accelerator preference: rc=$rc",
            )
        }
    }

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
     * Get default chip name based on architecture and device info.
     *
     * Tries to read from `Build.HARDWARE` and `/proc/cpuinfo`.
     */
    fun defaultChipName(architecture: String): String {
        // Try to get from Build.HARDWARE
        try {
            val buildClass = Class.forName("android.os.Build")
            val hardware = buildClass.getField("HARDWARE").get(null) as? String
            if (!hardware.isNullOrEmpty() && hardware != "unknown") {
                return hardware
            }
        } catch (e: Exception) {
            // Fall through
        }

        // Try to read from /proc/cpuinfo
        try {
            val cpuInfo = java.io.File("/proc/cpuinfo").readText()
            // Look for "Hardware" line
            val hardwareLine = cpuInfo.lines().find { it.startsWith("Hardware", ignoreCase = true) }
            if (hardwareLine != null) {
                val chipName = hardwareLine.substringAfter(":").trim()
                if (chipName.isNotEmpty()) {
                    return chipName
                }
            }
        } catch (e: Exception) {
            // Fall through
        }

        // Fallback to architecture as last resort
        return architecture
    }

    /**
     * Get default GPU family based on chip name.
     *
     * Infers GPU vendor from known chip manufacturers:
     * - Samsung Exynos -> Mali
     * - Qualcomm Snapdragon -> Adreno
     * - MediaTek -> Mali (mostly)
     * - HiSilicon Kirin -> Mali
     * - Google Tensor -> Mali
     * - Apple -> Apple
     */
    fun defaultGpuFamily(chipName: String): String {
        val chipLower = chipName.lowercase()

        return when {
            // Samsung Exynos uses Mali GPUs
            chipLower.contains("exynos") -> "mali"
            chipLower.startsWith("s5e") -> "mali" // Samsung internal chip naming (e.g., s5e8535)
            chipLower.contains("samsung") -> "mali"

            // Qualcomm Snapdragon uses Adreno GPUs
            chipLower.contains("snapdragon") -> "adreno"
            chipLower.contains("qualcomm") -> "adreno"
            chipLower.contains("sdm") -> "adreno" // SDM845, SDM855, etc.
            chipLower.contains("sm8") -> "adreno" // SM8150, SM8250, etc.
            chipLower.contains("sm7") -> "adreno" // SM7150, etc.
            chipLower.contains("sm6") -> "adreno" // SM6150, etc.
            chipLower.contains("msm") -> "adreno" // Older MSM chips

            // MediaTek uses Mali GPUs (mostly)
            chipLower.contains("mediatek") -> "mali"
            chipLower.contains("mt6") -> "mali" // MT6xxx series
            chipLower.contains("mt8") -> "mali" // MT8xxx series
            chipLower.contains("dimensity") -> "mali"
            chipLower.contains("helio") -> "mali"

            // HiSilicon Kirin uses Mali GPUs
            chipLower.contains("kirin") -> "mali"
            chipLower.contains("hisilicon") -> "mali"

            // Google Tensor uses Mali GPUs
            chipLower.contains("tensor") -> "mali"
            chipLower.contains("gs1") -> "mali" // GS101 (Tensor)
            chipLower.contains("gs2") -> "mali" // GS201 (Tensor G2)

            // Intel/x86 GPUs
            chipLower.contains("intel") -> "intel"

            // NVIDIA (rare on mobile)
            chipLower.contains("nvidia") -> "nvidia"
            chipLower.contains("tegra") -> "nvidia"

            else -> "unknown"
        }
    }
}
