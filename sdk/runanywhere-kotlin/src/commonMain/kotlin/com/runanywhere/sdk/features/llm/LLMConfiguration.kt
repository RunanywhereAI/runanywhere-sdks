package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.core.capabilities.ComponentConfiguration
import com.runanywhere.sdk.core.capabilities.ComponentInitParameters
import com.runanywhere.sdk.core.capabilities.SDKComponent
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.models.ExecutionTarget
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.serialization.Serializable

/**
 * Hardware configuration for model execution
 */
@Serializable
data class HardwareConfiguration(
    /** Whether to prefer GPU execution */
    val preferGPU: Boolean = true,
    /** Minimum memory required in MB */
    val minMemoryMB: Int = 4096,
    /** Recommended number of threads */
    val recommendedThreads: Int = 4,
    /** Whether to use memory mapping */
    val useMmap: Boolean = true,
    /** Whether to lock memory */
    val lockMemory: Boolean = false,
)

/**
 * Quantization levels for model optimization - exact match with iOS QuantizationLevel
 */
@Serializable
enum class QuantizationLevel(
    val value: String,
) {
    Q2_K("Q2_K"),
    Q3_K_S("Q3_K_S"),
    Q3_K_M("Q3_K_M"),
    Q3_K_L("Q3_K_L"),
    Q4_0("Q4_0"),
    Q4_1("Q4_1"),
    Q4_K_S("Q4_K_S"),
    Q4_K_M("Q4_K_M"),
    Q5_0("Q5_0"),
    Q5_1("Q5_1"),
    Q5_K_S("Q5_K_S"),
    Q5_K_M("Q5_K_M"),
    Q6_K("Q6_K"),
    Q8_0("Q8_0"),
    F16("F16"),
    F32("F32"),
    IQ2_XXS("IQ2_XXS"),
    IQ2_XS("IQ2_XS"),
    IQ3_S("IQ3_S"),
    IQ3_XXS("IQ3_XXS"),
    IQ4_NL("IQ4_NL"),
    IQ4_XS("IQ4_XS"),
    ;

    companion object {
        fun fromValue(value: String): QuantizationLevel? = values().find { it.value == value }

        /**
         * Get quantization level by compression ratio
         */
        fun byCompressionRatio(high: Boolean = false): QuantizationLevel = if (high) Q4_K_M else Q8_0

        /**
         * Get quantization level optimized for speed
         */
        fun forSpeed(): QuantizationLevel = Q4_0

        /**
         * Get quantization level optimized for quality
         */
        fun forQuality(): QuantizationLevel = Q8_0
    }

    /**
     * Get estimated compression ratio
     */
    val compressionRatio: Float
        get() =
            when (this) {
                Q2_K -> 0.25f
                Q3_K_S, Q3_K_M, Q3_K_L -> 0.375f
                Q4_0, Q4_1, Q4_K_S, Q4_K_M -> 0.5f
                Q5_0, Q5_1, Q5_K_S, Q5_K_M -> 0.625f
                Q6_K -> 0.75f
                Q8_0 -> 1.0f
                F16 -> 2.0f
                F32 -> 4.0f
                else -> 0.5f // Default for IQ variants
            }
}

/**
 * Enhanced LLM Configuration with rich hardware-specific optimizations
 * Exact match with iOS LLMConfiguration structure and capabilities
 */
@Serializable
data class LLMConfiguration(
    // MARK: - Component Identification
    /** Model ID to load */
    override val modelId: String? = null,
    // MARK: - Model Loading Parameters
    /** Context length/window size */
    val contextLength: Int = 2048,
    /** Use GPU acceleration if available */
    val useGPUIfAvailable: Boolean = true,
    /** Quantization level for model optimization */
    val quantizationLevel: QuantizationLevel? = null,
    /** Token cache size in MB */
    val cacheSize: Int = 100,
    /** Optional system prompt to preload into context */
    val preloadContext: String? = null,
    // MARK: - Default Generation Parameters
    /** Default temperature for generation */
    val temperature: Double = 0.7,
    /** Default maximum tokens to generate */
    val maxTokens: Int = 100,
    /** Default system prompt */
    val systemPrompt: String? = null,
    /** Enable streaming by default */
    val streamingEnabled: Boolean = true,
    // MARK: - Hardware Optimization Parameters
    /** Number of CPU threads to use */
    val cpuThreads: Int? = null,
    /** Number of GPU layers to offload (hybrid execution) */
    val gpuLayers: Int? = null,
    /** Memory mapping mode */
    val memoryMapping: Boolean = true,
    /** Use memory locking to prevent swapping */
    val memoryLock: Boolean = false,
    /** NUMA node to bind to (for multi-socket systems) */
    val numaNode: Int? = null,
    // MARK: - Advanced Configuration
    /** RoPE (Rotary Position Embedding) frequency base */
    val ropeFreqBase: Float? = null,
    /** RoPE frequency scaling factor */
    val ropeFreqScale: Float? = null,
    /** Enable attention optimization */
    val optimizeAttention: Boolean = true,
    /** Batch size for processing multiple requests */
    val batchSize: Int = 1,
    /** Enable continuous batching */
    val continuousBatching: Boolean = false,
    /** Flash attention configuration */
    val flashAttention: Boolean = true,
    /** KV cache optimization */
    val kvCacheOptimization: Boolean = true,
    // MARK: - Framework-Specific Options
    /** The inference framework to use for generation */
    val framework: InferenceFramework? = null,
    /** Framework-specific configuration options */
    val frameworkOptions: Map<String, String> = emptyMap(),
    /** Preferred execution target */
    val preferredExecutionTarget: ExecutionTarget? = null,
    /** Hardware configuration override */
    val hardwareConfiguration: HardwareConfiguration? = null,
    // MARK: - Debugging and Monitoring
    /** Enable verbose logging */
    val verboseLogging: Boolean = false,
    /** Enable performance monitoring */
    val performanceMonitoring: Boolean = true,
    /** Enable memory usage tracking */
    val memoryTracking: Boolean = true,
) : ComponentConfiguration,
    ComponentInitParameters {
    override val componentType: SDKComponent
        get() = SDKComponent.LLM

    override fun validate() {
        // Context length validation
        if (contextLength <= 0 || contextLength > 32768) {
            throw SDKError.ValidationFailed("Context length must be between 1 and 32768, got $contextLength")
        }

        // Cache size validation
        if (cacheSize < 0 || cacheSize > 1000) {
            throw SDKError.ValidationFailed("Cache size must be between 0 and 1000 MB, got $cacheSize")
        }

        // Temperature validation
        if (temperature < 0.0 || temperature > 2.0) {
            throw SDKError.ValidationFailed("Temperature must be between 0.0 and 2.0, got $temperature")
        }

        // Max tokens validation
        if (maxTokens <= 0 || maxTokens > contextLength) {
            throw SDKError.ValidationFailed("Max tokens must be between 1 and context length ($contextLength), got $maxTokens")
        }

        // Hardware configuration validation
        cpuThreads?.let { threads ->
            if (threads <= 0 || threads > 64) {
                throw SDKError.ValidationFailed("CPU threads must be between 1 and 64, got $threads")
            }
        }

        gpuLayers?.let { layers ->
            if (layers < 0 || layers > 100) {
                throw SDKError.ValidationFailed("GPU layers must be between 0 and 100, got $layers")
            }
        }

        batchSize.let { size ->
            if (size <= 0 || size > 128) {
                throw SDKError.ValidationFailed("Batch size must be between 1 and 128, got $size")
            }
        }

        // RoPE parameter validation
        ropeFreqBase?.let { base ->
            if (base <= 0) {
                throw SDKError.ValidationFailed("RoPE frequency base must be positive, got $base")
            }
        }

        ropeFreqScale?.let { scale ->
            if (scale <= 0) {
                throw SDKError.ValidationFailed("RoPE frequency scale must be positive, got $scale")
            }
        }
    }

    /**
     * Get effective system prompt (preloadContext takes precedence over systemPrompt)
     */
    val effectiveSystemPrompt: String?
        get() = preloadContext ?: systemPrompt

    /**
     * Check if GPU acceleration is configured
     */
    val hasGPUAcceleration: Boolean
        get() = useGPUIfAvailable && (gpuLayers == null || gpuLayers > 0)

    /**
     * Get memory requirements estimate in bytes
     */
    fun getEstimatedMemoryRequirements(): Long {
        val baseMem = cacheSize * 1024 * 1024L // Cache size in bytes
        val contextMem = contextLength * 4L * 1024 // Rough estimate for context
        return baseMem + contextMem
    }

    /**
     * Create optimized configuration for mobile devices
     */
    fun forMobile(): LLMConfiguration =
        copy(
            contextLength = minOf(contextLength, 2048),
            cacheSize = minOf(cacheSize, 50),
            cpuThreads = minOf(cpuThreads ?: 4, 4),
            gpuLayers = minOf(gpuLayers ?: 16, 16),
            memoryMapping = true,
            memoryLock = false,
            batchSize = 1,
            continuousBatching = false,
            verboseLogging = false,
        )

    /**
     * Create optimized configuration for desktop/server
     */
    fun forDesktop(): LLMConfiguration =
        copy(
            contextLength = maxOf(contextLength, 4096),
            cacheSize = maxOf(cacheSize, 200),
            cpuThreads = cpuThreads ?: 8,
            gpuLayers = gpuLayers ?: 32,
            memoryMapping = true,
            memoryLock = true,
            batchSize = maxOf(batchSize, 2),
            continuousBatching = true,
            flashAttention = true,
            kvCacheOptimization = true,
        )

    /**
     * Create configuration optimized for speed
     */
    fun forSpeed(): LLMConfiguration =
        copy(
            quantizationLevel = quantizationLevel ?: QuantizationLevel.forSpeed(),
            useGPUIfAvailable = true,
            gpuLayers = gpuLayers ?: 64,
            flashAttention = true,
            kvCacheOptimization = true,
            optimizeAttention = true,
            memoryMapping = true,
        )

    /**
     * Create configuration optimized for quality
     */
    fun forQuality(): LLMConfiguration =
        copy(
            quantizationLevel = quantizationLevel ?: QuantizationLevel.forQuality(),
            contextLength = maxOf(contextLength, 4096),
            temperature = minOf(temperature, 0.3),
            flashAttention = false, // Disable for maximum precision
            performanceMonitoring = true,
        )

    /**
     * Create configuration with specific hardware constraints
     */
    fun withMemoryLimit(maxMemoryMB: Int): LLMConfiguration {
        val adjustedCacheSize = minOf(cacheSize, maxMemoryMB / 2)
        val adjustedContextLength = minOf(contextLength, (maxMemoryMB - adjustedCacheSize) * 256)

        return copy(
            cacheSize = adjustedCacheSize,
            contextLength = adjustedContextLength,
            memoryMapping = maxMemoryMB < 500, // Use memory mapping for low-memory systems
            quantizationLevel = quantizationLevel ?: if (maxMemoryMB < 1000) QuantizationLevel.Q4_K_M else QuantizationLevel.Q8_0,
        )
    }

    companion object {
        /**
         * Default configuration for general use
         */
        val DEFAULT = LLMConfiguration()

        /**
         * Configuration optimized for mobile devices
         */
        val MOBILE = DEFAULT.forMobile()

        /**
         * Configuration optimized for desktop/server
         */
        val DESKTOP = DEFAULT.forDesktop()

        /**
         * Configuration optimized for speed
         */
        val SPEED = DEFAULT.forSpeed()

        /**
         * Configuration optimized for quality
         */
        val QUALITY = DEFAULT.forQuality()

        /**
         * Configuration for low-memory systems
         */
        val LOW_MEMORY = DEFAULT.withMemoryLimit(500)
    }
}
