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
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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

    // Use lazy initialization to avoid memory pressure and allow garbage collection
    // Per SDK guidelines: service dependencies should use lazy initialization
    private val capabilityAnalyzer: CapabilityAnalyzer by lazy { CapabilityAnalyzer() }
    private val batteryMonitorService: BatteryMonitorService by lazy { createBatteryMonitorService() }
    private val thermalMonitorService: ThermalMonitorService by lazy { createThermalMonitorService() }

    private var cachedCapabilities: DeviceCapabilities? = null
    private var cacheTimestamp: Long = 0
    private val cacheMutex = Mutex()

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
     * Thread-safe implementation using mutex to prevent race conditions.
     */
    val capabilities: DeviceCapabilities
        get() = runBlocking {
            cacheMutex.withLock {
                val now = currentTimeMillis()
                val elapsedTime = now - cacheTimestamp

                // Check cache validity
                val cached = cachedCapabilities
                if (cached != null && elapsedTime < CACHE_VALIDITY_MS) {
                    return@runBlocking cached
                }

                // Compute new capabilities
                val computed = capabilityAnalyzer.analyzeCapabilities()

                // Update cache
                cachedCapabilities = computed
                cacheTimestamp = now

                return@runBlocking computed
            }
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
     * Thread-safe implementation using the same mutex as capabilities getter.
     */
    fun refreshCapabilities() = runBlocking {
        cacheMutex.withLock {
            cachedCapabilities = null
            cacheTimestamp = 0
        }
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
