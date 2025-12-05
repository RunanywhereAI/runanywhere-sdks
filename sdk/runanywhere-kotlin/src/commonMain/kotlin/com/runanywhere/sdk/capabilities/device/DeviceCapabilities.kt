package com.runanywhere.sdk.capabilities.device

import com.runanywhere.sdk.models.ModelInfo
import kotlinx.serialization.Serializable

/**
 * Memory pressure levels
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
 */
enum class MemoryPressureLevel {
    LOW,
    MEDIUM,
    HIGH,
    WARNING,
    CRITICAL
}

/**
 * Processor type enumeration
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
 */
enum class ProcessorType {
    // Apple A-series (iPhone/iPad)
    A14_BIONIC,
    A15_BIONIC,
    A16_BIONIC,
    A17_PRO,
    A18,
    A18_PRO,

    // Apple M-series (Mac/iPad Pro)
    M1,
    M1_PRO,
    M1_MAX,
    M1_ULTRA,
    M2,
    M2_PRO,
    M2_MAX,
    M2_ULTRA,
    M3,
    M3_PRO,
    M3_MAX,
    M4,
    M4_PRO,
    M4_MAX,

    // Other architectures
    INTEL,
    ARM,
    UNKNOWN;

    /**
     * Whether this processor is Apple Silicon
     */
    val isAppleSilicon: Boolean
        get() = when (this) {
            A14_BIONIC, A15_BIONIC, A16_BIONIC, A17_PRO, A18, A18_PRO,
            M1, M1_PRO, M1_MAX, M1_ULTRA,
            M2, M2_PRO, M2_MAX, M2_ULTRA,
            M3, M3_PRO, M3_MAX,
            M4, M4_PRO, M4_MAX -> true
            ARM, INTEL, UNKNOWN -> false
        }
}

/**
 * Operating system version info
 */
@Serializable
data class OperatingSystemVersion(
    val majorVersion: Int,
    val minorVersion: Int,
    val patchVersion: Int = 0
) {
    override fun toString(): String = "$majorVersion.$minorVersion.$patchVersion"

    companion object {
        /**
         * Parse version from string like "18.2.1" or "15.0"
         */
        fun parse(versionString: String): OperatingSystemVersion {
            val parts = versionString.split(".")
            return OperatingSystemVersion(
                majorVersion = parts.getOrNull(0)?.toIntOrNull() ?: 0,
                minorVersion = parts.getOrNull(1)?.toIntOrNull() ?: 0,
                patchVersion = parts.getOrNull(2)?.toIntOrNull() ?: 0
            )
        }
    }
}

/**
 * Complete device hardware capabilities
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
 */
data class DeviceCapabilities(
    val totalMemory: Long,
    val availableMemory: Long,
    val hasNeuralEngine: Boolean = false,
    val hasGPU: Boolean = false,
    val processorCount: Int,
    val processorType: ProcessorType = ProcessorType.UNKNOWN,
    val supportedAccelerators: List<HardwareAcceleration> = listOf(HardwareAcceleration.CPU),
    val osVersion: OperatingSystemVersion,
    val modelIdentifier: String = "Unknown"
) {
    /**
     * Memory pressure level based on available memory
     */
    val memoryPressureLevel: MemoryPressureLevel
        get() {
            val ratio = availableMemory.toDouble() / totalMemory.toDouble()
            return when {
                ratio < 0.1 -> MemoryPressureLevel.CRITICAL
                ratio < 0.15 -> MemoryPressureLevel.WARNING
                ratio < 0.2 -> MemoryPressureLevel.HIGH
                ratio < 0.4 -> MemoryPressureLevel.MEDIUM
                else -> MemoryPressureLevel.LOW
            }
        }

    /**
     * Whether the device has sufficient resources for a given model
     */
    fun canRun(model: ModelInfo): Boolean {
        val memoryRequired = model.memoryRequired ?: 0L
        return availableMemory >= memoryRequired
    }

    companion object {
        /**
         * Create default capabilities with minimal information
         */
        fun default(
            totalMemory: Long,
            processorCount: Int
        ): DeviceCapabilities = DeviceCapabilities(
            totalMemory = totalMemory,
            availableMemory = totalMemory,
            processorCount = processorCount,
            osVersion = OperatingSystemVersion(0, 0, 0)
        )
    }
}
