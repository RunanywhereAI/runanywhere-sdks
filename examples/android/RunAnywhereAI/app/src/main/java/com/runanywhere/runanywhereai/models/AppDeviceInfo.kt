/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Example-app device info adapter. Composes `RunAnywhere.hardware` (proto
 * `HardwareProfile`) with `android.os.Build` for display fields the SDK's
 * canonical hardware profile does not carry (model name, OS version string).
 *
 * This replaces the deleted SDK `com.runanywhere.sdk.models.DeviceInfo`.
 */

package com.runanywhere.runanywhereai.models

import android.os.Build
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.hardware

/**
 * Display-layer device info used by the Benchmark dashboard and Model
 * selection sheet. Purely for example-app UI; not an SDK type.
 *
 * `modelName` and `osVersion` come from `android.os.Build` (not in the
 * canonical `HardwareProfile` proto). Everything else is sourced from
 * `RunAnywhere.hardware.getProfile()`.
 */
data class AppDeviceInfo(
    val modelName: String,
    val architecture: String,
    val totalMemory: Long,
    val totalMemoryMB: Long,
    val osVersion: String,
) {
    companion object {
        /**
         * Snapshot the current device state. Safe to call on any thread;
         * `RunAnywhere.hardware.getProfile()` is synchronous.
         */
        fun current(): AppDeviceInfo {
            val profile = RunAnywhere.hardware.getProfile().profile
            val chipOrArch =
                profile?.chip?.ifBlank { null }
                    ?: profile?.architecture?.ifBlank { null }
                    ?: Build.HARDWARE
            val totalBytes = profile?.total_memory_bytes ?: 0L
            return AppDeviceInfo(
                modelName = Build.MODEL ?: "Unknown",
                architecture = chipOrArch,
                totalMemory = totalBytes,
                totalMemoryMB = if (totalBytes > 0) totalBytes / (1024L * 1024L) else 0L,
                osVersion = Build.VERSION.RELEASE ?: "unknown",
            )
        }
    }
}
