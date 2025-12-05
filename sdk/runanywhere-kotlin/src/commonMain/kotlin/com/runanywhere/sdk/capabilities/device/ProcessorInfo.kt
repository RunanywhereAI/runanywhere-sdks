package com.runanywhere.sdk.capabilities.device

import kotlinx.serialization.Serializable

/**
 * Processor generation enumeration
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/ProcessorInfo.swift
 */
@Serializable
enum class ProcessorGeneration(val value: String) {
    GENERATION_1("gen1"),  // A14, M1
    GENERATION_2("gen2"),  // A15, M2
    GENERATION_3("gen3"),  // A16, M3
    GENERATION_4("gen4"),  // A17 Pro, M4
    GENERATION_5("gen5"),  // A18, A18 Pro
    UNKNOWN("unknown");

    companion object {
        fun fromValue(value: String): ProcessorGeneration {
            return entries.find { it.value == value } ?: UNKNOWN
        }
    }
}

/**
 * Performance tier classification
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/ProcessorInfo.swift
 */
@Serializable
enum class PerformanceTier(val value: String) {
    FLAGSHIP("flagship"),
    HIGH("high"),
    MEDIUM("medium"),
    ENTRY("entry");

    companion object {
        fun fromValue(value: String): PerformanceTier {
            return entries.find { it.value == value } ?: ENTRY
        }
    }
}

/**
 * Processor information
 *
 * Matches iOS: Capabilities/DeviceCapability/Models/ProcessorInfo.swift
 */
@Serializable
data class ProcessorInfo(
    val chipName: String = "Unknown",
    val coreCount: Int,
    val performanceCores: Int = 0,
    val efficiencyCores: Int = 0,
    val architecture: String,
    val hasARM64E: Boolean = false,
    val clockFrequency: Double = 0.0,  // GHz
    val l2CacheSize: Long = 0,          // bytes
    val l3CacheSize: Long = 0,          // bytes
    val neuralEngineCores: Int = 0,
    val estimatedTops: Float = 0.0f
) {
    /**
     * Processor generation - determined from chip name
     */
    val generation: ProcessorGeneration = when {
        chipName.contains("A18") || chipName.contains("M4") -> ProcessorGeneration.GENERATION_5
        chipName.contains("A17") || chipName.contains("M3") -> ProcessorGeneration.GENERATION_4
        chipName.contains("A16") || chipName.contains("M2") -> ProcessorGeneration.GENERATION_3
        chipName.contains("A15") || chipName.contains("M1") -> ProcessorGeneration.GENERATION_2
        chipName.contains("A14") -> ProcessorGeneration.GENERATION_1
        else -> ProcessorGeneration.UNKNOWN
    }

    /**
     * Whether this processor has a neural engine
     */
    val hasNeuralEngine: Boolean = neuralEngineCores > 0

    /**
     * Whether this is an Apple Silicon processor
     */
    val isAppleSilicon: Boolean
        get() = architecture.lowercase().contains("arm") && hasARM64E

    /**
     * Whether this is an Intel processor
     */
    val isIntel: Boolean
        get() = architecture.lowercase().contains("x86")

    /**
     * Total cache size
     */
    val totalCacheSize: Long
        get() = l2CacheSize + l3CacheSize

    /**
     * Performance tier based on estimated TOPS
     */
    val performanceTier: PerformanceTier
        get() = when {
            estimatedTops >= 35f -> PerformanceTier.FLAGSHIP
            estimatedTops >= 15f -> PerformanceTier.HIGH
            estimatedTops >= 10f -> PerformanceTier.MEDIUM
            else -> PerformanceTier.ENTRY
        }

    /**
     * Recommended batch size based on performance tier
     */
    val recommendedBatchSize: Int
        get() = when (performanceTier) {
            PerformanceTier.FLAGSHIP -> 8
            PerformanceTier.HIGH -> 4
            PerformanceTier.MEDIUM -> 2
            PerformanceTier.ENTRY -> 1
        }

    /**
     * Whether concurrent inference is supported
     */
    val supportsConcurrentInference: Boolean
        get() = performanceCores >= 4 && neuralEngineCores >= 16

    companion object {
        /**
         * Create a basic ProcessorInfo with minimal information
         */
        fun basic(
            coreCount: Int,
            architecture: String
        ): ProcessorInfo = ProcessorInfo(
            coreCount = coreCount,
            architecture = architecture
        )
    }
}
