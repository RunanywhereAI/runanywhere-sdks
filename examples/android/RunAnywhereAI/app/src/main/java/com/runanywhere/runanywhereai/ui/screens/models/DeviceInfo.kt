package com.runanywhere.runanywhereai.ui.screens.models

import android.os.Build
import java.io.File

data class DeviceInfo(
    val model: String,
    val chip: String,
    val memoryMb: Long,
) {
    companion object {
        // Device info is a UI display concern, not SDK business logic, so it reads
        // Android platform APIs directly. (The SDK's hardware-profile API was removed
        // when the routing scorer was retired — the engine router no longer needs a
        // hardware profile, so the SDK no longer surfaces one.)
        fun current(): DeviceInfo {
            val chip = socModel()?.ifBlank { null }
                ?: Build.HARDWARE.ifBlank { null }
                ?: "Unknown"
            return DeviceInfo(
                model = Build.MODEL ?: "Unknown",
                chip = chip,
                memoryMb = totalMemoryMb(),
            )
        }

        private fun socModel(): String? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else null

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
