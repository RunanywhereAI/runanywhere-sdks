package com.runanywhere.runanywhereai.ui.screens.models

import android.os.Build
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.hardware

data class DeviceInfo(
    val model: String,
    val chip: String,
    val memoryMb: Long,
) {
    companion object {
        fun current(): DeviceInfo {
            val profile = RunAnywhere.hardware.getProfile().profile
            val chip = profile?.chip?.ifBlank { null }
                ?: profile?.architecture?.ifBlank { null }
                ?: Build.HARDWARE
            val bytes = profile?.total_memory_bytes ?: 0L
            return DeviceInfo(
                model = Build.MODEL ?: "Unknown",
                chip = chip,
                memoryMb = if (bytes > 0) bytes / (1024L * 1024L) else 0L,
            )
        }
    }
}
