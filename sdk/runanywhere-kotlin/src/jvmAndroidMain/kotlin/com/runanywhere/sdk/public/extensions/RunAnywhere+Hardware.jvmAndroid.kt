/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the hardware profile namespace.
 *
 * Round 2 KOTLIN: Wires the racHardwareProfileGet JNI thunk added by the
 * C++ round 1 fix. Falls back to platform APIs when the C++ thunk is not
 * yet available (UnsatisfiedLinkError caught internally).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.HardwareProfile
import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.foundation.device.PhysicalMemoryProbe
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere

actual class Hardware {
    actual fun getProfile(): HardwareProfileResult {
        return try {
            val bytes = RunAnywhereBridge.racHardwareProfileGet()
            if (bytes != null && bytes.isNotEmpty()) {
                HardwareProfileResult.ADAPTER.decode(bytes)
            } else {
                buildPlatformProfile()
            }
        } catch (e: UnsatisfiedLinkError) {
            buildPlatformProfile()
        }
    }

    actual fun getChip(): String = getProfile().profile?.chip?.ifBlank { "Unknown" } ?: "Unknown"

    actual val hasNeuralEngine: Boolean
        get() = getProfile().profile?.has_neural_engine ?: false

    actual val accelerationMode: String
        get() = getProfile().profile?.acceleration_mode?.ifBlank { "cpu" } ?: "cpu"

    private fun buildPlatformProfile(): HardwareProfileResult {
        val runtime = Runtime.getRuntime()
        val cpuCores = runtime.availableProcessors()
        // G-DV20: Report physical device RAM. Runtime.maxMemory() returns the
        // JVM heap cap (~512 MB on Android) and is NOT a device-memory probe.
        val totalMemoryMB = PhysicalMemoryProbe.totalPhysicalMemoryMB()
        val chipName =
            try {
                // On Android, ro.board.platform gives the SoC name.
                val process = Runtime.getRuntime().exec(arrayOf("getprop", "ro.board.platform"))
                val chip =
                    process.inputStream
                        .bufferedReader()
                        .readLine()
                        ?.trim() ?: ""
                chip.ifBlank { "Unknown" }
            } catch (e: Throwable) {
                "Unknown"
            }
        // Fallback reports platform facts only. Accelerator/routing capability
        // must come from rac_hardware_profile_get when the native bridge is
        // available, not from Kotlin chip-name heuristics.
        return HardwareProfileResult(
            profile =
                HardwareProfile(
                    chip = chipName,
                    has_neural_engine = false,
                    acceleration_mode = "cpu",
                    total_memory_bytes = totalMemoryMB * 1024L * 1024L,
                    core_count = cpuCores,
                    architecture = System.getProperty("os.arch") ?: "",
                    platform = "android",
                ),
        )
    }
}

private val hardwareInstance = Hardware()

actual val RunAnywhere.hardware: Hardware
    get() = hardwareInstance
