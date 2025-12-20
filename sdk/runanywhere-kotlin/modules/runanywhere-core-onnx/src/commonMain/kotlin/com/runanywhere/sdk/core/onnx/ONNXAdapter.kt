package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.features.llm.HardwareConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.frameworks.ComponentInitParameters
import com.runanywhere.sdk.core.frameworks.DownloadStrategy
import com.runanywhere.sdk.core.frameworks.ModelStorageStrategy
import com.runanywhere.sdk.core.frameworks.UnifiedFrameworkAdapter
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * ONNX Runtime Framework Adapter
 *
 * Unified adapter for ONNX Runtime, supporting multiple modalities:
 * - Speech-to-Text (Whisper, Zipformer, Paraformer)
 * - Text-to-Speech (Piper, VITS)
 * - Voice Activity Detection (Silero VAD)
 * - Text Generation (future)
 *
 * Matches iOS ONNXAdapter
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXAdapter.swift
 */
class ONNXAdapter : UnifiedFrameworkAdapter {

    private val logger = SDKLogger("ONNXAdapter")

    // Cached service instances for reuse
    private var cachedSTTService: Any? = null
    private var cachedTTSService: Any? = null
    private var lastSTTUsage: Long? = null
    private var lastTTSUsage: Long? = null
    private val cacheTimeout: Long = 300_000 // 5 minutes in milliseconds

    // MARK: - UnifiedFrameworkAdapter Properties

    override val framework: InferenceFramework = InferenceFramework.ONNX

    override val supportedModalities: Set<FrameworkModality> = setOf(
        FrameworkModality.VOICE_TO_TEXT,
        FrameworkModality.TEXT_TO_VOICE
        // Note: TEXT_TO_TEXT not yet implemented - removed to avoid contract violation
    )

    override val supportedFormats: List<ModelFormat> = listOf(
        ModelFormat.ONNX,
        ModelFormat.ORT
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

        // Check framework compatibility
        if (model.compatibleFrameworks.isNotEmpty()) {
            return model.compatibleFrameworks.contains(InferenceFramework.ONNX)
        }

        // Check by model ID patterns
        val modelId = model.id.lowercase()
        return modelId.contains("onnx") ||
                modelId.contains("zipformer") ||
                modelId.contains("sherpa") ||
                modelId.contains("piper") ||
                modelId.contains("vits") ||
                modelId.contains("silero")
    }

    /**
     * Create a service instance for the given modality
     */
    override fun createService(modality: FrameworkModality): Any? {
        cleanupStaleCache()

        return when (modality) {
            FrameworkModality.VOICE_TO_TEXT -> {
                lastSTTUsage = currentTimeMillis()
                cachedSTTService
            }
            FrameworkModality.TEXT_TO_VOICE -> {
                lastTTSUsage = currentTimeMillis()
                cachedTTSService
            }
            else -> {
                logger.warning("Modality $modality not supported by ONNX adapter")
                null
            }
        }
    }

    /**
     * Load a model and return a service instance
     */
    override suspend fun loadModel(model: ModelInfo, modality: FrameworkModality): Any {
        logger.info("Loading model ${model.id} for modality $modality")

        val localPath = model.localPath
            ?: throw ONNXError.ModelNotFound(model.id)

        return when (modality) {
            FrameworkModality.VOICE_TO_TEXT -> {
                val service = createONNXSTTServiceFromPath(localPath)
                cachedSTTService = service
                lastSTTUsage = currentTimeMillis()
                service
            }
            FrameworkModality.TEXT_TO_VOICE -> {
                val service = createONNXTTSServiceFromPath(localPath)
                cachedTTSService = service
                lastTTSUsage = currentTimeMillis()
                service
            }
            else -> {
                throw ONNXError.NotImplemented
            }
        }
    }

    /**
     * Configure adapter with hardware settings
     */
    override suspend fun configure(hardware: HardwareConfiguration) {
        logger.debug("Configuring ONNX adapter with hardware: $hardware")
        // ONNX Runtime configuration is handled at service level
    }

    /**
     * Estimate memory usage for a model
     * Matches iOS estimateMemoryUsage(for:) implementation
     */
    override fun estimateMemoryUsage(model: ModelInfo): Long {
        // Base estimate: file size + 30% overhead for runtime
        val baseSize = model.memoryRequired ?: model.downloadSize ?: 0L
        return (baseSize * 1.3).toLong()
    }

    /**
     * Get optimal hardware configuration for a model
     */
    override fun optimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return HardwareConfiguration(
            preferGPU = false, // ONNX uses CPU on mobile by default
            minMemoryMB = (estimateMemoryUsage(model) / 1024 / 1024).toInt(),
            recommendedThreads = 4 // Default thread count for cross-platform compatibility
        )
    }

    /**
     * Called when this adapter is registered with ModuleRegistry
     * Registers STT, TTS, and VAD providers
     */
    override fun onRegistration() {
        logger.info("ONNX adapter registration - registering service providers")

        // Register STT provider
        ModuleRegistry.shared.registerSTT(ONNXSTTServiceProvider())

        // Register TTS provider
        ModuleRegistry.shared.registerTTS(ONNXTTSServiceProvider())

        // Register VAD provider
        ModuleRegistry.shared.registerVAD(ONNXVADServiceProvider())

        logger.info("Registered ONNX STT, TTS, and VAD providers with ModuleRegistry")
    }

    /**
     * Get models provided by this adapter
     * Returns empty - models are discovered from external sources
     */
    override fun getProvidedModels(): List<ModelInfo> {
        return emptyList()
    }

    /**
     * Get download strategy for ONNX models
     */
    override fun getDownloadStrategy(): DownloadStrategy? {
        return ONNXDownloadStrategy()
    }

    /**
     * Get model storage strategy for ONNX models
     * Used to detect downloaded models on disk with ONNX-specific structures
     */
    override fun getModelStorageStrategy(): ModelStorageStrategy? {
        return ONNXModelStorageStrategy()
    }

    /**
     * Initialize a component with parameters
     */
    override suspend fun initializeComponent(
        parameters: ComponentInitParameters,
        modality: FrameworkModality
    ): Any? {
        val modelId = parameters.modelId ?: return createService(modality)

        // If model ID is provided, try to find and load it
        // In practice, the calling code should resolve the ModelInfo first
        logger.info("Initializing ONNX component for model: $modelId, modality: $modality")

        return createService(modality)
    }

    // MARK: - Private Methods

    /**
     * Cleanup cached services that haven't been used recently
     */
    private fun cleanupStaleCache() {
        val now = currentTimeMillis()

        lastSTTUsage?.let { lastUsage ->
            if (now - lastUsage > cacheTimeout) {
                logger.debug("Cleaning up stale STT service cache")
                cachedSTTService = null
                lastSTTUsage = null
            }
        }

        lastTTSUsage?.let { lastUsage ->
            if (now - lastUsage > cacheTimeout) {
                logger.debug("Cleaning up stale TTS service cache")
                cachedTTSService = null
                lastTTSUsage = null
            }
        }
    }

    companion object {
        /**
         * Singleton instance
         */
        val shared: ONNXAdapter = ONNXAdapter()

        /**
         * Register the ONNX adapter with ModuleRegistry
         * @param priority Registration priority (higher = selected first)
         */
        fun register(priority: Int = 100) {
            ModuleRegistry.shared.registerFrameworkAdapter(shared, priority)
        }
    }
}

// Platform-specific service creation (expect declarations)

/**
 * Create ONNX STT service from model path
 */
expect suspend fun createONNXSTTServiceFromPath(modelPath: String): Any

/**
 * Create ONNX TTS service from model path
 */
expect suspend fun createONNXTTSServiceFromPath(modelPath: String): Any
