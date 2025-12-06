package com.runanywhere.sdk.capabilities.device

import kotlinx.serialization.Serializable

/**
 * Device information for compatibility checking
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/DeviceInfo.swift
 */
@Serializable
data class DeviceInfo(
    val model: String,
    val osVersion: String,
    val architecture: String,
    val totalMemory: Long,
    val availableMemory: Long,
    val hasNeuralEngine: Boolean,
    val gpuFamily: String? = null
) {
    companion object {
        /**
         * Create unknown device info (placeholder)
         */
        val unknown: DeviceInfo = DeviceInfo(
            model = "Unknown",
            osVersion = "Unknown",
            architecture = "Unknown",
            totalMemory = 0L,
            availableMemory = 0L,
            hasNeuralEngine = false,
            gpuFamily = null
        )
    }
}
