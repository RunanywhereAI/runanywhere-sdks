/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for hardware profile — namespaced as `RunAnywhere.hardware.*`
 * per CANONICAL_API.md §14.
 *
 * Round 2 KOTLIN: Implements the hardware namespace that was CPP-BLOCKED in
 * Round 1. The C++ round 1 fix added `rac_hardware_profile_get` and
 * hardware_profile.proto — this file wires the Kotlin surface.
 */

package com.runanywhere.sdk.public.extensions

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
 * println("Chip: ${hw.getChip()}")
 * if (hw.hasNeuralEngine) println("NPU available")
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
     * Short chip / SoC name (e.g. "Apple M4 Pro", "Snapdragon 8 Gen 3").
     *
     * @return Chip name string, or "Unknown" if not available
     */
    fun getChip(): String

    /**
     * Whether the device has a dedicated neural processing unit.
     */
    val hasNeuralEngine: Boolean

    /**
     * Active hardware acceleration mode.
     *
     * @return Mode string (e.g. "NPU", "GPU", "CPU", "Unknown")
     */
    val accelerationMode: String
}

// ---------------------------------------------------------------------------
// RunAnywhere.hardware accessor
// ---------------------------------------------------------------------------

/**
 * Namespace accessor for hardware profile operations.
 */
expect val RunAnywhere.hardware: Hardware
