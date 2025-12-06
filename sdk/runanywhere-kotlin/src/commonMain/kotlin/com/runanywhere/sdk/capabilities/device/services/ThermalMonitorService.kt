package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.ThermalState
import kotlinx.coroutines.flow.Flow

/**
 * Service for monitoring device thermal state
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/ThermalMonitorService.swift
 *
 * Platform-specific implementations:
 * - Android: Uses PowerManager.getThermalHeadroom (API 29+)
 * - JVM: Returns NOMINAL (no thermal monitoring on desktop)
 */
interface ThermalMonitorService {
    /**
     * Get current thermal state
     *
     * @return Current thermal state of the device
     */
    fun getCurrentThermalState(): ThermalState

    /**
     * Observe thermal state changes as a Flow
     *
     * @return Flow emitting thermal state updates
     */
    fun observeThermalStateChanges(): Flow<ThermalState>
}

/**
 * Factory for creating platform-specific ThermalMonitorService instances
 */
expect fun createThermalMonitorService(): ThermalMonitorService
