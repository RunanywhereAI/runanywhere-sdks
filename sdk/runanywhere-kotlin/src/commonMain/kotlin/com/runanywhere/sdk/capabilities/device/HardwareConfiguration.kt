package com.runanywhere.sdk.capabilities.device

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Memory management mode
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/HardwareConfiguration.swift
 */
@Serializable
enum class MemoryMode(val value: String) {
    CONSERVATIVE("conservative"),
    BALANCED("balanced"),
    AGGRESSIVE("aggressive");

    companion object {
        fun fromValue(value: String): MemoryMode {
            return entries.find { it.value == value } ?: BALANCED
        }
    }
}

/**
 * Simplified hardware configuration for framework adapters
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/HardwareConfiguration.swift
 */
@Serializable
data class HardwareConfiguration(
    /**
     * Primary hardware accelerator to use (auto will select best available)
     */
    val primaryAccelerator: HardwareAcceleration = HardwareAcceleration.AUTO,

    /**
     * Memory management mode
     */
    val memoryMode: MemoryMode = MemoryMode.BALANCED,

    /**
     * Number of CPU threads to use for processing.
     * Default is calculated at runtime using platform-specific APIs.
     */
    val threadCount: Int = DEFAULT_THREAD_COUNT
) {
    companion object {
        /**
         * Default thread count, calculated at runtime
         */
        @Transient
        private val DEFAULT_THREAD_COUNT: Int
            get() = PlatformSystemInfo.getAvailableProcessors()

        /**
         * Create default configuration
         */
        fun default(): HardwareConfiguration = HardwareConfiguration()

        /**
         * Create configuration optimized for low memory
         */
        fun lowMemory(): HardwareConfiguration = HardwareConfiguration(
            primaryAccelerator = HardwareAcceleration.CPU,
            memoryMode = MemoryMode.CONSERVATIVE,
            threadCount = minOf(2, PlatformSystemInfo.getAvailableProcessors())
        )

        /**
         * Create configuration optimized for performance
         */
        fun highPerformance(): HardwareConfiguration = HardwareConfiguration(
            primaryAccelerator = HardwareAcceleration.AUTO,
            memoryMode = MemoryMode.AGGRESSIVE,
            threadCount = PlatformSystemInfo.getAvailableProcessors()
        )
    }
}
