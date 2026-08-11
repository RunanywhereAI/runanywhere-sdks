package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.HexagonArch
import android.os.Build
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import java.io.File

// Coarse hardware capability bucket used to size model recommendations. Resolved
// from device RAM plus NPU presence; NPU devices are promoted a tier since the
// Hexagon accelerator lets them run heavier bundles than RAM alone would suggest.
enum class HardwareTier(val label: String) {
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
    // Human-facing one-liner for the device card, e.g. "High-performance • NPU accelerated".
    val tierSummary: String
        get() = if (hasNpu) "${tier.label} • NPU accelerated" else tier.label

    companion object {
        // RAM thresholds (MB) separating the tiers. High-end flagships ship 8 GB+,
        // mid-range devices sit in the 4–8 GB band, everything below is low-end.
        private const val HIGH_END_MEMORY_MB = 7_500L
        private const val MID_RANGE_MEMORY_MB = 3_500L

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
                tier = resolveTier(memoryMb, hasNpu),
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

        private fun resolveTier(memoryMb: Long, hasNpu: Boolean): HardwareTier {
            val base = when {
                memoryMb >= HIGH_END_MEMORY_MB -> HardwareTier.HIGH_END
                memoryMb >= MID_RANGE_MEMORY_MB -> HardwareTier.MID_RANGE
                else -> HardwareTier.LOW_END
            }
            // A Hexagon NPU offloads heavy work off the CPU/GPU, so promote NPU devices
            // one tier (never above HIGH_END) to unlock the accelerated model set.
            if (!hasNpu) return base
            return when (base) {
                HardwareTier.LOW_END -> HardwareTier.MID_RANGE
                HardwareTier.MID_RANGE -> HardwareTier.HIGH_END
                HardwareTier.HIGH_END -> HardwareTier.HIGH_END
            }
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
