/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the hardware profile namespace.
 *
 * Wave 3a KOT-HARDWARE-FALLBACK: Delegates exclusively to
 * `rac_hardware_profile_get` via the `racHardwareProfileGet` JNI thunk.
 * The previous Kotlin-side `Runtime.exec("getprop ro.board.platform")`
 * fallback is gone — chip/accelerator detection lives entirely in the
 * C++ `rac_hardware_abi.cpp` implementation, which already reads
 * `ro.hardware.chipname` / `ro.board.platform` via `__system_property_get`
 * on Android and populates core count / architecture / platform.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere

actual class Hardware {
    actual fun getProfile(): HardwareProfileResult {
        val bytes = RunAnywhereBridge.racHardwareProfileGet()
        return if (bytes != null && bytes.isNotEmpty()) {
            HardwareProfileResult.ADAPTER.decode(bytes)
        } else {
            HardwareProfileResult()
        }
    }

    actual fun getChip(): String = getProfile().profile?.chip?.ifBlank { "Unknown" } ?: "Unknown"

    actual val hasNeuralEngine: Boolean
        get() = getProfile().profile?.has_neural_engine ?: false

    actual val accelerationMode: String
        get() = getProfile().profile?.acceleration_mode?.ifBlank { "cpu" } ?: "cpu"
}

private val hardwareInstance = Hardware()

actual val RunAnywhere.hardware: Hardware
    get() = hardwareInstance
