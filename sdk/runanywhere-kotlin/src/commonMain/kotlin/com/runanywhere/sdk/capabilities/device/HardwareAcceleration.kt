package com.runanywhere.sdk.capabilities.device

/**
 * Hardware acceleration options
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/HardwareAcceleration.swift
 */
enum class HardwareAcceleration(val value: String) {
    CPU("CPU"),
    GPU("GPU"),
    NEURAL_ENGINE("NeuralEngine"),
    METAL("Metal"),
    CORE_ML("CoreML"),
    AUTO("Auto");

    companion object {
        fun fromValue(value: String): HardwareAcceleration {
            return entries.find { it.value.equals(value, ignoreCase = true) } ?: AUTO
        }
    }
}
