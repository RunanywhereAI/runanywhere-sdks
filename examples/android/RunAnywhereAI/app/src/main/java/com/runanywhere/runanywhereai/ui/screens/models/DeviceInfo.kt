package com.runanywhere.runanywhereai.ui.screens.models

import android.os.Build
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

        // Device info is a UI display concern, not SDK business logic, so it reads
        // Android platform APIs directly. (The SDK's hardware-profile API was removed
        // when the routing scorer was retired — the engine router no longer needs a
        // hardware profile, so the SDK no longer surfaces one.)
        fun current(): DeviceInfo {
            val soc = socModel()
            val chip = soc?.ifBlank { null }
                ?: Build.HARDWARE.ifBlank { null }
                ?: "Unknown"
            val memoryMb = totalMemoryMb()
            val npuName = detectHexagonNpu(soc)
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

        private fun socManufacturer(): String? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else null

        // Heuristic Qualcomm Hexagon NPU detection. Device-only truth is only known at
        // runtime — QHexRT's native bundle resolver ultimately gates real support — so
        // this errs toward flagship Snapdragon SoCs we know ship a Hexagon v79/v81 NPU.
        // Returns a friendly NPU name, or null when no Hexagon NPU is inferred.
        private fun detectHexagonNpu(soc: String?): String? {
            val manufacturer = socManufacturer()?.trim().orEmpty()
            val isQualcomm = manufacturer.equals("QTI", ignoreCase = true) ||
                manufacturer.equals("Qualcomm", ignoreCase = true)
            val model = soc?.trim().orEmpty().uppercase()

            // SM8xxx is the flagship Snapdragon 8-series line (e.g. SM8750 = 8 Elite,
            // SM8850 = next-gen) — all carry a Hexagon NPU. SM7550+ high-end 7-series
            // parts also ship a capable Hexagon, so we treat those as NPU-capable too.
            val isFlagshipSnapdragon = model.startsWith("SM8") ||
                model.startsWith("SM7550") || model.startsWith("SM7635")

            if (!isQualcomm && !isFlagshipSnapdragon) return null
            return hexagonNameFor(model)
        }

        private fun hexagonNameFor(socModel: String): String = when {
            socModel.startsWith("SM8850") -> "Hexagon v81 NPU"
            socModel.startsWith("SM8750") -> "Hexagon v79 NPU"
            socModel.startsWith("SM8650") -> "Hexagon v75 NPU"
            socModel.startsWith("SM8") -> "Hexagon NPU"
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
