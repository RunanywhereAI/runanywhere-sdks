package com.runanywhere.runanywhereai.presentation.models

/**
 * Device information data class
 * Shared across all model-related views
 */
data class DeviceInfo(
    val model: String,
    val processor: String,
    val androidVersion: String,
    val cores: Int
)
