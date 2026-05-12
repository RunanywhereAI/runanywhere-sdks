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

import ai.runanywhere.proto.v1.AcceleratorInfo
import ai.runanywhere.proto.v1.AccelerationPreference
import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.public.RunAnywhere

// ---------------------------------------------------------------------------
// Hardware — namespaced capability class
// ---------------------------------------------------------------------------

/**
 * Provides hardware profile information for the current device.
 *
 * Access via `RunAnywhere.hardware`.
 *
 * Example:
 * ```kotlin
 * val hw = RunAnywhere.hardware
 * val profile = hw.getProfile()
 * val accelerators = hw.getAccelerators()
 * hw.setAcceleratorPreference(AccelerationPreference.ACCELERATION_PREFERENCE_GPU)
 * ```
 */
expect class Hardware {
    /**
     * Retrieve the full hardware profile.
     *
     * @return generated [HardwareProfileResult] describing the current device hardware
     */
    fun getProfile(): HardwareProfileResult

    /**
     * Get available accelerators as generated proto data.
     *
     * Mirrors Swift `RunAnywhere.hardware.getAccelerators()`.
     *
     * @return list of [AcceleratorInfo] entries for the current device.
     */
    suspend fun getAccelerators(): List<AcceleratorInfo>

    /**
     * Set the preferred accelerator for subsequent routing / inference calls.
     *
     * Mirrors Swift `RunAnywhere.hardware.setAcceleratorPreference(_:)`.
     *
     * @param pref The [AccelerationPreference] to apply to future engine
     *             routing decisions.
     */
    suspend fun setAcceleratorPreference(pref: AccelerationPreference)
}

// ---------------------------------------------------------------------------
// RunAnywhere.hardware accessor
// ---------------------------------------------------------------------------

/**
 * Namespace accessor for hardware profile operations.
 */
expect val RunAnywhere.hardware: Hardware
