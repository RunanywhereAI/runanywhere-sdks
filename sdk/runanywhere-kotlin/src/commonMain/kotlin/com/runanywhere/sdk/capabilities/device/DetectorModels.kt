package com.runanywhere.sdk.capabilities.device

import kotlinx.serialization.Serializable

/**
 * Processor efficiency rating
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/ProcessorDetector.swift
 */
enum class ProcessorEfficiency {
    HIGH,
    MEDIUM,
    LOW
}

/**
 * Processor features/capabilities
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/ProcessorDetector.swift
 */
enum class ProcessorFeature {
    /** ARM NEON SIMD instructions */
    NEON,
    /** Vector processing unit */
    VECTOR_UNIT,
    /** Neural Engine (Apple Silicon) */
    NEURAL_ENGINE,
    /** SSE instructions (Intel) */
    SSE,
    /** AVX instructions (Intel) */
    AVX,
    /** AVX2 instructions (Intel) */
    AVX2
}

/**
 * Neural Engine generations
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/NeuralEngineDetector.swift
 */
enum class NeuralEngineVersion {
    /** A12-A15 series */
    GENERATION_1,
    /** M1 series */
    GENERATION_2,
    /** M2 series and later */
    GENERATION_3
}

/**
 * Supported precisions for Neural Engine
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/NeuralEngineDetector.swift
 */
enum class NeuralEnginePrecision {
    INT8,
    FLOAT16,
    FLOAT32
}

/**
 * Neural Engine capabilities information
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/NeuralEngineDetector.swift
 */
@Serializable
data class NeuralEngineCapabilities(
    val version: NeuralEngineVersion,
    val operationsPerSecond: Long,
    val supportedPrecisions: List<NeuralEnginePrecision>,
    val maxModelSize: Long
) {
    companion object {
        /**
         * Operations per second estimates by generation
         */
        fun estimatedOps(version: NeuralEngineVersion): Long = when (version) {
            NeuralEngineVersion.GENERATION_1 -> 5_000_000_000_000L  // 5 TOPS
            NeuralEngineVersion.GENERATION_2 -> 11_000_000_000_000L // 11 TOPS
            NeuralEngineVersion.GENERATION_3 -> 15_000_000_000_000L // 15+ TOPS
        }

        /**
         * Default max model size (1GB)
         */
        const val DEFAULT_MAX_MODEL_SIZE: Long = 1_000_000_000L
    }
}

/**
 * GPU performance tiers
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/GPUDetector.swift
 */
enum class GPUPerformanceTier {
    LOW,
    MEDIUM,
    HIGH
}

/**
 * GPU capabilities information
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/GPUDetector.swift
 */
@Serializable
data class GPUCapabilities(
    val name: String,
    val family: String,
    val maxBufferLength: Long,
    val supportsComputeShaders: Boolean,
    val supportsMetalPerformanceShaders: Boolean,
    val recommendedMaxWorkingSetSize: Long
) {
    /**
     * Estimated performance tier based on max buffer length
     */
    val performanceTier: GPUPerformanceTier
        get() = when {
            maxBufferLength > 1_000_000_000L -> GPUPerformanceTier.HIGH
            maxBufferLength > 256_000_000L -> GPUPerformanceTier.MEDIUM
            else -> GPUPerformanceTier.LOW
        }

    companion object {
        /**
         * Create a basic GPU capabilities with minimal info
         */
        fun basic(name: String, family: String): GPUCapabilities = GPUCapabilities(
            name = name,
            family = family,
            maxBufferLength = 256_000_000L,
            supportsComputeShaders = true,
            supportsMetalPerformanceShaders = false,
            recommendedMaxWorkingSetSize = 256_000_000L
        )
    }
}
