package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.HardwareConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.frameworks.ComponentInitParameters
import com.runanywhere.sdk.core.frameworks.DownloadStrategy
import com.runanywhere.sdk.core.frameworks.UnifiedFrameworkAdapter
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.QuantizationLevel
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * LlamaCPP Framework Adapter
 *
 * Unified adapter for llama.cpp, supporting:
 * - Text-to-Text generation (LLM)
 * - GGUF and GGML model formats
 *
 * Matches iOS LlamaCPPCoreAdapter
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPPCoreAdapter.swift
 */
class LlamaCppAdapter : UnifiedFrameworkAdapter {

    private val logger = SDKLogger("LlamaCppAdapter")

    // Cached service for reuse
    private var cachedService: LlamaCppService? = null
    private var lastUsage: Long? = null
    private val cacheTimeout: Long = 300_000 // 5 minutes

    // MARK: - UnifiedFrameworkAdapter Properties

    override val framework: LLMFramework = LLMFramework.LLAMA_CPP

    override val supportedModalities: Set<FrameworkModality> = setOf(
        FrameworkModality.TEXT_TO_TEXT
    )

    override val supportedFormats: List<ModelFormat> = listOf(
        ModelFormat.GGUF,
        ModelFormat.GGML
    )

    // Supported quantization levels
    private val supportedQuantizations = setOf(
        QuantizationLevel.Q4_0, QuantizationLevel.Q4_1, QuantizationLevel.Q4_K_S, QuantizationLevel.Q4_K_M,
        QuantizationLevel.Q5_0, QuantizationLevel.Q5_1, QuantizationLevel.Q5_K_S, QuantizationLevel.Q5_K_M,
        QuantizationLevel.Q6_K, QuantizationLevel.Q8_0,
        QuantizationLevel.Q2_K, QuantizationLevel.Q3_K_S, QuantizationLevel.Q3_K_M, QuantizationLevel.Q3_K_L,
        QuantizationLevel.F16, QuantizationLevel.F32
    )

    // MARK: - UnifiedFrameworkAdapter Methods

    /**
     * Check if this adapter can handle the given model
     * Matches iOS canHandle(model:) implementation
     */
    override fun canHandle(model: ModelInfo): Boolean {
        // Check format support
        if (!supportedFormats.contains(model.format)) {
            return false
        }

        // Check quantization compatibility
        model.metadata?.quantizationLevel?.let { quantization ->
            if (!supportedQuantizations.contains(quantization)) {
                return false
            }
        }

        // Check memory requirements (70% of available memory)
        val availableMemory = Runtime.getRuntime().maxMemory()
        val requiredMemory = model.memoryRequired ?: 0L
        if (requiredMemory > availableMemory * 0.7) {
            logger.warning("Model ${model.id} may not fit in memory: required=$requiredMemory, available=$availableMemory")
            // Still allow - let the user decide
        }

        return true
    }

    /**
     * Create a service instance for the given modality
     */
    @Synchronized
    override fun createService(modality: FrameworkModality): Any? {
        cleanupStaleCache()

        if (modality != FrameworkModality.TEXT_TO_TEXT) {
            logger.warning("Modality $modality not supported by LlamaCpp adapter")
            return null
        }

        lastUsage = currentTimeMillis()
        return cachedService
    }

    /**
     * Load a model and return a service instance
     * Note: Thread safety handled via synchronized blocks internally
     */
    override suspend fun loadModel(model: ModelInfo, modality: FrameworkModality): Any {
        logger.info("Loading model ${model.id} for modality $modality")

        if (modality != FrameworkModality.TEXT_TO_TEXT) {
            throw LlamaCppError.UnsupportedModality(modality.name)
        }

        val localPath = model.localPath
            ?: throw LlamaCppError.ModelNotFound(model.id)

        val config = com.runanywhere.sdk.components.llm.LLMConfiguration(
            modelId = model.id,
            contextLength = model.contextLength ?: 4096,
            useGPUIfAvailable = false
        )

        // Cleanup previous cached service before loading new model
        cachedService?.let {
            logger.debug("Cleaning up previous cached service before loading new model")
            // Note: If LlamaCppService has a cleanup/dispose method, it should be called here
        }
        cachedService = null

        val service = LlamaCppService(config)
        service.initialize(localPath)

        cachedService = service
        lastUsage = currentTimeMillis()

        return service
    }

    /**
     * Configure adapter with hardware settings
     */
    override suspend fun configure(hardware: HardwareConfiguration) {
        logger.debug("Configuring LlamaCpp adapter with hardware: $hardware")
        // Hardware configuration is handled at service initialization
    }

    /**
     * Estimate memory usage for a model
     * Matches iOS estimateMemoryUsage(for:) implementation
     */
    override fun estimateMemoryUsage(model: ModelInfo): Long {
        // Base estimate: file size + 30% overhead for context and KV cache
        val baseSize = model.memoryRequired ?: model.downloadSize ?: 0L
        return (baseSize * 1.3).toLong()
    }

    /**
     * Get optimal hardware configuration for a model
     */
    override fun optimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return HardwareConfiguration(
            preferGPU = false, // CPU-only for now on mobile
            minMemoryMB = (estimateMemoryUsage(model) / 1024 / 1024).toInt(),
            recommendedThreads = Runtime.getRuntime().availableProcessors()
        )
    }

    /**
     * Called when this adapter is registered with ModuleRegistry
     * Registers the LLM provider
     */
    override fun onRegistration() {
        logger.info("LlamaCpp adapter registration - registering LLM provider")
        LlamaCppServiceProvider.register()
        logger.info("Registered LlamaCppServiceProvider with ModuleRegistry")
    }

    /**
     * Get models provided by this adapter
     * Returns empty - models are discovered from external sources
     */
    override fun getProvidedModels(): List<ModelInfo> {
        return emptyList()
    }

    /**
     * Get download strategy for LlamaCpp models
     * Returns null - GGUF files are downloaded directly
     */
    override fun getDownloadStrategy(): DownloadStrategy? {
        return null
    }

    /**
     * Initialize a component with parameters
     * Matches iOS initializeComponent implementation - uses createService for initialization
     */
    override suspend fun initializeComponent(
        parameters: ComponentInitParameters,
        modality: FrameworkModality
    ): Any? {
        val modelId = parameters.modelId
        if (modelId != null) {
            logger.info("Initializing LlamaCpp component for model: $modelId")
        }

        // Use createService for initialization (matches iOS pattern)
        return createService(modality)
    }

    // MARK: - Private Methods

    /**
     * Cleanup cached service that hasn't been used recently
     */
    @Synchronized
    private fun cleanupStaleCache() {
        lastUsage?.let { lastUsageTime ->
            if (currentTimeMillis() - lastUsageTime > cacheTimeout) {
                logger.debug("Cleaning up stale LlamaCpp service cache")
                cachedService = null
                lastUsage = null
            }
        }
    }

    companion object {
        /**
         * Singleton instance
         */
        val shared: LlamaCppAdapter = LlamaCppAdapter()

        /**
         * Register the LlamaCpp adapter with ModuleRegistry
         * @param priority Registration priority (higher = selected first)
         */
        fun register(priority: Int = 100) {
            ModuleRegistry.shared.registerFrameworkAdapter(shared, priority)
        }
    }
}

/**
 * Error types for LlamaCpp operations
 */
sealed class LlamaCppError : Exception() {

    /** Model not found or not downloaded */
    data class ModelNotFound(val modelId: String) : LlamaCppError() {
        override val message: String = "Model not found or not downloaded: $modelId"
    }

    /** Modality not supported */
    data class UnsupportedModality(val modality: String) : LlamaCppError() {
        override val message: String = "Modality not supported by LlamaCpp: $modality"
    }

    /** Initialization failed */
    object InitializationFailed : LlamaCppError() {
        private fun readResolve(): Any = InitializationFailed
        override val message: String = "LlamaCpp initialization failed"
    }

    /** Model load failed */
    data class ModelLoadFailed(val details: String) : LlamaCppError() {
        override val message: String = "Model load failed: $details"
    }

    /** Generation failed */
    data class GenerationFailed(val details: String) : LlamaCppError() {
        override val message: String = "Generation failed: $details"
    }

    /** Invalid handle */
    object InvalidHandle : LlamaCppError() {
        private fun readResolve(): Any = InvalidHandle
        override val message: String = "Invalid backend handle"
    }

    /** Operation cancelled */
    object Cancelled : LlamaCppError() {
        private fun readResolve(): Any = Cancelled
        override val message: String = "Operation cancelled"
    }
}
