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

import com.runanywhere.sdk.public.RunAnywhere

// ---------------------------------------------------------------------------
// HardwareProfile — canonical descriptor for the current device hardware.
// ---------------------------------------------------------------------------

/**
 * Hardware profile for the current device.
 *
 * Mirrors the proto type `HardwareProfileResult` from `hardware_profile.proto`.
 *
 * @param chipName Human-readable chip / SoC name (e.g. "Apple M4 Pro", "Snapdragon 8 Gen 3")
 * @param hasNeuralEngine Whether the device has a dedicated neural processing unit
 * @param accelerationMode Active acceleration mode (e.g. "GPU", "NPU", "CPU")
 * @param totalMemoryMB Total device RAM in megabytes, or 0 if unknown
 * @param cpuCores Number of logical CPU cores
 */
data class HardwareProfile(
    val chipName: String,
    val hasNeuralEngine: Boolean,
    val accelerationMode: String,
    val totalMemoryMB: Long = 0L,
    val cpuCores: Int = 0,
)

/**
 * Canonical alias matching `HardwareProfileResult` from the generated proto
 * type (`commonMain/.../generated/runanywhere/v1/HardwareProfileResult.kt`).
 * Wave 3 Step 3.2: lets callers spell the type as `HardwareProfileResult`
 * per CANONICAL_API §14, ahead of the Wave 4 type unification.
 */
typealias HardwareProfileResult = HardwareProfile

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
     * @return [HardwareProfile] describing the current device hardware
     */
    fun getProfile(): HardwareProfile

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
