package com.runanywhere.sdk.public.extensions

import android.os.Build
import com.runanywhere.sdk.core.types.NPUChip
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Android implementation of NPU chip detection.
 *
 * Detection strategy (ordered):
 * 1. [Build.SOC_MODEL] (API 31+) — e.g. "SM8750"
 * 2. [Build.HARDWARE] — fallback codename
 * 3. /proc/cpuinfo Hardware line — last resort
 */
actual fun RunAnywhere.getChip(): NPUChip? {
    val logger = SDKLogger("NPUChip")

    // 1. Try Build.SOC_MODEL (API 31+)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val socModel = Build.SOC_MODEL
        if (!socModel.isNullOrEmpty() && socModel != "unknown") {
            val chip = NPUChip.fromSocModel(socModel)
            if (chip != null) {
                logger.info("Detected NPU chip: ${chip.displayName} (SOC_MODEL=$socModel)")
                return chip
            }
        }
    }

    // 2. Try Build.HARDWARE
    val hardware = Build.HARDWARE
    if (!hardware.isNullOrEmpty() && hardware != "unknown") {
        val chip = NPUChip.fromSocModel(hardware)
        if (chip != null) {
            logger.info("Detected NPU chip: ${chip.displayName} (HARDWARE=$hardware)")
            return chip
        }
    }

    // 3. Try /proc/cpuinfo
    try {
        val cpuInfo = java.io.File("/proc/cpuinfo").readText()
        val hardwareLine = cpuInfo.lines().find { it.startsWith("Hardware", ignoreCase = true) }
        if (hardwareLine != null) {
            val cpuHardware = hardwareLine.substringAfter(":").trim()
            val chip = NPUChip.fromSocModel(cpuHardware)
            if (chip != null) {
                logger.info("Detected NPU chip: ${chip.displayName} (cpuinfo=$cpuHardware)")
                return chip
            }
        }
    } catch (_: Exception) {
        // Fall through
    }

    logger.debug("No supported NPU chip detected")
    return null
}
