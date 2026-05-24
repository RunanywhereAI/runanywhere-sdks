/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for hardware profile — namespaced as `RunAnywhere.hardware.*`
 * per CANONICAL_API.md §14.
 *
 * Mirrors Swift `RunAnywhere+Hardware.swift` exactly:
 *   - getProfile()              -> HardwareProfileResult
 *   - getAccelerators()         -> List<AcceleratorInfo>
 *   - setAcceleratorPreference(pref)
 *
 * Apple-only / Android-only chip / NPU / acceleration-mode probes live in
 * `CppBridgeHardware` (platform fallbacks) and are not part of the public
 * surface — they were removed in W1-K2-6 to match Swift's narrow API.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AccelerationPreference
import ai.runanywhere.proto.v1.AcceleratorInfo
import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeHardware
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

// ---------------------------------------------------------------------------
// Hardware — namespaced capability class
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// RunAnywhere.hardware accessor
// ---------------------------------------------------------------------------

class Hardware {
    fun getProfile(): HardwareProfileResult = CppBridgeHardware.getProfile()

    suspend fun getAccelerators(): List<AcceleratorInfo> {
        // TODO: Wire `rac_hardware_get_accelerators` once a JNI thunk
        //       (`racHardwareGetAccelerators`) is bound in
        //       sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp.
        //       Until then the Kotlin surface matches Swift's "not supported"
        //       fallback behaviour (rac_result_t == RAC_ERROR_NOT_SUPPORTED).
        throw SDKException.notImplemented("Hardware.getAccelerators")
    }

    suspend fun setAcceleratorPreference(pref: AccelerationPreference) {
        // TODO: Wire `rac_hardware_set_accelerator_preference(pref.value)`
        //       once a JNI thunk (`racHardwareSetAcceleratorPreference`) is
        //       bound in
        //       sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp.
        //       Until then the Kotlin surface matches Swift's "not supported"
        //       fallback behaviour (rac_result_t == RAC_ERROR_NOT_SUPPORTED).
        throw SDKException.notImplemented("Hardware.setAcceleratorPreference")
    }
}

private val hardwareInstance = Hardware()

val RunAnywhere.hardware: Hardware
    get() = hardwareInstance
