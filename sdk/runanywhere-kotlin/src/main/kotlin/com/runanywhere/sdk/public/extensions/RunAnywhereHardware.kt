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
import com.runanywhere.sdk.public.RunAnywhere

// Hardware — namespaced capability class

// RunAnywhere.hardware accessor

class Hardware {
    fun getProfile(): HardwareProfileResult = CppBridgeHardware.getProfile()

    /**
     * Get available accelerators (NNAPI / GPU / NPU / etc.) as canonical proto
     * data. Mirrors Swift `CppBridge.Hardware.getAccelerators()` which decodes
     * the same `RAHardwareProfileResult` shape but exposes only its
     * `accelerators` list (the `profile` field is left empty by the commons
     * ABI for this entry point).
     */
    fun getAccelerators(): List<AcceleratorInfo> = CppBridgeHardware.getAccelerators()

    /**
     * Set the preferred accelerator for subsequent inference calls. Mirrors
     * Swift `CppBridge.Hardware.setAcceleratorPreference(_:)`. Throws
     * `SDKException` on commons rc != RAC_SUCCESS.
     */
    fun setAcceleratorPreference(pref: AccelerationPreference) =
        CppBridgeHardware.setAcceleratorPreference(pref)
}

private val hardwareInstance = Hardware()

val RunAnywhere.hardware: Hardware
    get() = hardwareInstance
