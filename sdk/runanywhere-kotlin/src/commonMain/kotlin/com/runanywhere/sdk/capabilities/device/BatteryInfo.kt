package com.runanywhere.sdk.capabilities.device

import kotlinx.serialization.Serializable

/**
 * Battery charging state
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/BatteryInfo.swift
 */
@Serializable
enum class BatteryState(val value: String) {
    UNKNOWN("unknown"),
    UNPLUGGED("unplugged"),
    CHARGING("charging"),
    FULL("full");

    companion object {
        fun fromValue(value: String): BatteryState {
            return entries.find { it.value == value } ?: UNKNOWN
        }
    }
}

/**
 * Battery information for device power status
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/BatteryInfo.swift
 */
@Serializable
data class BatteryInfo(
    /**
     * Battery level from 0.0 to 1.0 (null if unknown)
     */
    val level: Float?,

    /**
     * Current battery state
     */
    val state: BatteryState,

    /**
     * Whether the device is in low power mode
     */
    val isLowPowerModeEnabled: Boolean = false
) {
    /**
     * Check if battery is low (less than 20%)
     */
    val isLowBattery: Boolean
        get() = level?.let { it < 0.2f } ?: false

    /**
     * Check if battery is critical (less than 10%)
     */
    val isCriticalBattery: Boolean
        get() = level?.let { it < 0.1f } ?: false

    companion object {
        /**
         * Create unknown battery info
         */
        val unknown: BatteryInfo = BatteryInfo(
            level = null,
            state = BatteryState.UNKNOWN,
            isLowPowerModeEnabled = false
        )
    }
}
