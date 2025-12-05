package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.BatteryInfo

/**
 * Service for monitoring device battery state
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/BatteryMonitorService.swift
 *
 * Platform-specific implementations:
 * - Android: Uses BatteryManager and PowerManager
 * - JVM: Returns unknown state (no battery monitoring on desktop)
 */
interface BatteryMonitorService {
    /**
     * Get current battery information
     *
     * @return BatteryInfo with current level, state, and power mode, or null if unavailable
     */
    fun getBatteryInfo(): BatteryInfo?

    /**
     * Check if device is in low power mode
     *
     * @return true if low power mode is enabled, false otherwise
     */
    fun isLowPowerMode(): Boolean
}

/**
 * Factory for creating platform-specific BatteryMonitorService instances
 */
expect fun createBatteryMonitorService(): BatteryMonitorService
