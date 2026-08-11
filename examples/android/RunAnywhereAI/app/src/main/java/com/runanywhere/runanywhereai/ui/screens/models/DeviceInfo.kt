package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.HexagonArch
import android.os.Build
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import java.io.File

// Display bucket for device capability. Commons does not yet publish a typed
// capability tier on DeviceInfo, so the example surfaces UNKNOWN rather than
// inventing RAM thresholds or NPU promotion.
enum class HardwareTier(val label: String) {
    UNKNOWN("Unknown"),
    HIGH_END("High-performance"),
    MID_RANGE("Balanced"),
    LOW_END("Lightweight"),
}

data class DeviceInfo(
    val model: String,
    val chip: String,
    val memoryMb: Long,
    val hasNpu: Boolean,
    val npuName: String?,
    val tier: HardwareTier,
) {
    // Human-facing one-liner for the device card. Tier label is only shown when
    // a typed tier exists; otherwise NPU presence alone (from QHexRT.probeNpu).
    val tierSummary: String
        get() = when (tier) {
            HardwareTier.UNKNOWN ->
                if (hasNpu) "NPU accelerated" else "Capabilities unknown"
            else ->
                if (hasNpu) "${tier.label} • NPU accelerated" else tier.label
        }

    companion object {
        // Device card display: RAM from /proc/meminfo; NPU from QHexRT.probeNpu()
        // (commons-owned Hexagon capability), not SOC_MODEL string heuristics.
        fun current(): DeviceInfo {
            val soc = socModel()
            val chip = soc?.ifBlank { null }
                ?: Build.HARDWARE.ifBlank { null }
                ?: "Unknown"
            val memoryMb = totalMemoryMb()
            val npu = runCatching { QHexRT.probeNpu() }.getOrNull()
            val npuName = npu?.takeIf { it.supported }?.let { hexagonDisplayName(it.hexagon_arch) }
            val hasNpu = npuName != null
            return DeviceInfo(
                model = Build.MODEL ?: "Unknown",
                chip = chip,
                memoryMb = memoryMb,
                hasNpu = hasNpu,
                npuName = npuName,
                tier = HardwareTier.UNKNOWN,
            )
        }

        private fun socModel(): String? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else null

        private fun hexagonDisplayName(arch: HexagonArch): String = when (arch) {
            HexagonArch.HEXAGON_ARCH_V81 -> "Hexagon v81 NPU"
            HexagonArch.HEXAGON_ARCH_V79 -> "Hexagon v79 NPU"
            HexagonArch.HEXAGON_ARCH_V75 -> "Hexagon v75 NPU"
            else -> "Hexagon NPU"
        }

        // MemTotal from /proc/meminfo (kB) → MB. Context-free; 0 if unavailable.
        private fun totalMemoryMb(): Long =
            try {
                File("/proc/meminfo").bufferedReader().useLines { lines ->
                    lines.firstOrNull { it.startsWith("MemTotal:") }
                        ?.filter { it.isDigit() }
                        ?.toLongOrNull()
                        ?.div(1024L)
                        ?: 0L
                }
            } catch (_: Exception) {
                0L
            }
    }
}
