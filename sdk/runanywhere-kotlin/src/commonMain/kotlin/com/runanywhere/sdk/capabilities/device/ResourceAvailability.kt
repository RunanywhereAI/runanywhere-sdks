package com.runanywhere.sdk.capabilities.device

import com.runanywhere.sdk.models.ModelInfo

/**
 * Resource availability information
 *
 * Matches iOS: Core/Models/Common/ResourceAvailability.swift
 */
data class ResourceAvailability(
    val memoryAvailable: Long,
    val storageAvailable: Long,
    val acceleratorsAvailable: List<HardwareAcceleration>,
    val thermalState: ThermalState,
    val batteryLevel: Float? = null,
    val isLowPowerMode: Boolean = false
) {
    /**
     * Result of checking if a model can be loaded
     */
    data class LoadCheckResult(
        val canLoad: Boolean,
        val reason: String? = null
    )

    /**
     * Check if a model can be loaded with current resources
     */
    fun canLoad(model: ModelInfo): LoadCheckResult {
        // Check memory
        val memoryNeeded = model.memoryRequired ?: 0L
        if (memoryNeeded > memoryAvailable) {
            val neededStr = formatBytes(memoryNeeded)
            val availableStr = formatBytes(memoryAvailable)
            return LoadCheckResult(
                canLoad = false,
                reason = "Insufficient memory: need $neededStr, have $availableStr"
            )
        }

        // Check storage
        val downloadSize = model.downloadSize
        if (downloadSize != null && downloadSize > storageAvailable) {
            val neededStr = formatBytes(downloadSize)
            val availableStr = formatBytes(storageAvailable)
            return LoadCheckResult(
                canLoad = false,
                reason = "Insufficient storage: need $neededStr, have $availableStr"
            )
        }

        // Check thermal state
        if (thermalState == ThermalState.CRITICAL) {
            return LoadCheckResult(
                canLoad = false,
                reason = "Device is too hot, please wait for it to cool down"
            )
        }

        // Check battery in low power mode
        if (isLowPowerMode) {
            val battery = batteryLevel
            if (battery != null && battery < 0.2f) {
                return LoadCheckResult(
                    canLoad = false,
                    reason = "Battery too low for model loading in Low Power Mode"
                )
            }
        }

        return LoadCheckResult(canLoad = true, reason = null)
    }

    companion object {
        /**
         * Format bytes as human-readable string
         */
        private fun formatBytes(bytes: Long): String {
            val kb = 1024L
            val mb = kb * 1024
            val gb = mb * 1024

            return when {
                bytes >= gb -> String.format("%.1f GB", bytes.toDouble() / gb)
                bytes >= mb -> String.format("%.1f MB", bytes.toDouble() / mb)
                bytes >= kb -> String.format("%.1f KB", bytes.toDouble() / kb)
                else -> "$bytes bytes"
            }
        }

        /**
         * Create default resource availability
         */
        fun default(): ResourceAvailability = ResourceAvailability(
            memoryAvailable = PlatformSystemInfo.getFreeMemory(),
            storageAvailable = 0L,
            acceleratorsAvailable = listOf(HardwareAcceleration.CPU),
            thermalState = ThermalState.NOMINAL
        )
    }
}
