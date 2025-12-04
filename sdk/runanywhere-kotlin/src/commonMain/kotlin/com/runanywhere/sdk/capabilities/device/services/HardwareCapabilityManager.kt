package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.BatteryInfo
import com.runanywhere.sdk.capabilities.device.DeviceCapabilities
import com.runanywhere.sdk.capabilities.device.HardwareAcceleration
import com.runanywhere.sdk.capabilities.device.HardwareConfiguration
import com.runanywhere.sdk.capabilities.device.MemoryPressureLevel
import com.runanywhere.sdk.capabilities.device.ResourceAvailability
import com.runanywhere.sdk.capabilities.device.ThermalState
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.ModelInfo

/**
 * Manager for hardware capability detection and configuration
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/HardwareDetectionService.swift
 * (Note: iOS file is named HardwareDetectionService but class is HardwareCapabilityManager)
 */
class HardwareCapabilityManager private constructor() {

    companion object {
        /**
         * Shared singleton instance
         */
        val shared: HardwareCapabilityManager by lazy { HardwareCapabilityManager() }

        /** Cache validity duration in milliseconds (1 minute) */
        private const val CACHE_VALIDITY_MS = 60_000L
    }

    // MARK: - Properties

    private val logger = SDKLogger("HardwareCapabilityManager")
    private val capabilityAnalyzer: CapabilityAnalyzer = CapabilityAnalyzer()
    private val batteryMonitorService: BatteryMonitorService = createBatteryMonitorService()
    private val thermalMonitorService: ThermalMonitorService = createThermalMonitorService()

    private var cachedCapabilities: DeviceCapabilities? = null
    private var cacheTimestamp: Long = 0

    /**
     * Device identifier for compilation cache
     */
    val deviceIdentifier: String
        get() = capabilities.modelIdentifier

    // MARK: - Public API

    /**
     * Get current device capabilities
     *
     * Capabilities are cached for 1 minute to avoid expensive recalculation.
     */
    val capabilities: DeviceCapabilities
        get() {
            val now = currentTimeMillis()
            val elapsedTime = now - cacheTimestamp

            // Check cache validity
            val cached = cachedCapabilities
            if (cached != null && elapsedTime < CACHE_VALIDITY_MS) {
                return cached
            }

            // Compute new capabilities
            val computed = capabilityAnalyzer.analyzeCapabilities()

            // Update cache
            cachedCapabilities = computed
            cacheTimestamp = now

            return computed
        }

    /**
     * Get optimal hardware configuration for a model
     */
    fun optimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return capabilityAnalyzer.getOptimalConfiguration(model)
    }

    /**
     * Check resource availability
     */
    fun checkResourceAvailability(): ResourceAvailability {
        val caps = capabilities
        val batteryInfo = getBatteryInfo()
        val thermalState = getThermalState()

        return ResourceAvailability(
            memoryAvailable = caps.availableMemory,
            storageAvailable = getAvailableStorage(),
            acceleratorsAvailable = caps.supportedAccelerators,
            thermalState = thermalState,
            batteryLevel = batteryInfo?.level,
            isLowPowerMode = batteryInfo?.isLowPowerModeEnabled ?: false
        )
    }

    /**
     * Refresh cached capabilities
     */
    fun refreshCapabilities() {
        cachedCapabilities = null
        cacheTimestamp = 0
    }

    /**
     * Check if a specific accelerator is available
     */
    fun isAcceleratorAvailable(accelerator: HardwareAcceleration): Boolean {
        return capabilities.supportedAccelerators.contains(accelerator)
    }

    /**
     * Get memory pressure level
     */
    val memoryPressureLevel: MemoryPressureLevel
        get() = capabilities.memoryPressureLevel

    // MARK: - Private Methods

    private fun getAvailableStorage(): Long {
        // Platform-specific implementation would go here
        // For now, return 0 (unknown)
        return 0L
    }

    private fun getThermalState(): ThermalState {
        return thermalMonitorService.getCurrentThermalState()
    }

    private fun getBatteryInfo(): BatteryInfo? {
        return batteryMonitorService.getBatteryInfo()
    }
}
