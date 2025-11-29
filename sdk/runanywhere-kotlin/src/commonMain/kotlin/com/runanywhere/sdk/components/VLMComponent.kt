package com.runanywhere.sdk.components

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.base.ComponentConfiguration
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.generation.GenerationOptions
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.VLMServiceProvider
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable

/**
 * VLM Component for vision-language model processing
 * One-to-one mapping from iOS VLMComponent.swift
 */
class VLMComponent(
    private val vlmConfiguration: VLMConfiguration
) : BaseComponent<VLMService>(vlmConfiguration) {

    override val componentType: SDKComponent = SDKComponent.VLM

    private var currentModel: ModelInfo? = null
    private val _isProcessing = MutableStateFlow(false)
    val isProcessing: StateFlow<Boolean> = _isProcessing.asStateFlow()

    override suspend fun createService(): VLMService {
        // Create service from registry or default implementation
        val provider = ModuleRegistry.vlmProvider(vlmConfiguration.modelId)
        return if (provider != null) {
            VLMServiceAdapter(provider)
        } else {
            DefaultVLMService()
        }
    }

    override suspend fun initializeService() {
        // Initialize service
        service = createService()

        // Load model if specified
        vlmConfiguration.modelId?.let { modelId ->
            // Model loading will be handled by the service provider
        }
    }

    /**
     * Analyze an image
     */
    suspend fun analyze(
        image: ByteArray,
        prompt: String? = null
    ): VLMOutput {
        ensureReady()

        _isProcessing.value = true
        return try {
            service?.analyze(
                image = image,
                prompt = prompt ?: "Describe this image",
                modelId = currentModel?.id ?: "default"
            ) ?: throw IllegalStateException("VLM service not initialized")
        } finally {
            _isProcessing.value = false
        }
    }

    /**
     * Generate text from image with prompt
     */
    suspend fun generateFromImage(
        image: ByteArray,
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): String {
        ensureReady()

        _isProcessing.value = true
        return try {
            service?.generateFromImage(
                image = image,
                prompt = prompt,
                modelId = currentModel?.id ?: "default",
                options = options
            ) ?: throw IllegalStateException("VLM service not initialized")
        } finally {
            _isProcessing.value = false
        }
    }

    /**
     * Analyze multiple images
     */
    suspend fun analyzeMultiple(
        images: List<ByteArray>,
        prompt: String? = null
    ): List<VLMOutput> {
        ensureReady()

        return images.map { image ->
            analyze(image, prompt)
        }
    }

    /**
     * Stream analysis results
     */
    fun analyzeStream(
        image: ByteArray,
        prompt: String? = null
    ): Flow<VLMStreamOutput> {
        ensureReady()

        return flow {
            _isProcessing.value = true
            try {
                service?.analyzeStream(
                    image = image,
                    prompt = prompt ?: "Describe this image",
                    modelId = currentModel?.id ?: "default"
                )?.collect { output ->
                    emit(output)
                } ?: throw IllegalStateException("VLM service not initialized")
            } finally {
                _isProcessing.value = false
            }
        }
    }

    /**
     * Detect objects in image
     */
    suspend fun detectObjects(
        image: ByteArray,
        threshold: Float = 0.5f
    ): List<DetectedObject> {
        ensureReady()

        val output = analyze(image, "Detect all objects in this image")
        return output.detectedObjects.filter { it.confidence >= threshold }
    }

    /**
     * Extract text from image (OCR)
     */
    suspend fun extractText(
        image: ByteArray,
        languages: List<String> = listOf("en")
    ): String {
        ensureReady()

        val output = analyze(image, "Extract all text from this image")
        return output.extractedText ?: ""
    }

    /**
     * Load a specific model
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        transitionTo(ComponentState.INITIALIZING)

        try {
            // Load model (implementation would depend on the model format)
            currentModel = modelInfo
            service?.loadModel(modelInfo)
            transitionTo(ComponentState.READY)
        } catch (e: Exception) {
            transitionTo(ComponentState.FAILED)
            throw e
        }
    }

    /**
     * Cancel current processing
     */
    fun cancelProcessing() {
        _isProcessing.value = false
        service?.cancelCurrent()
    }
}

/**
 * VLM Output
 */
@Serializable
data class VLMOutput(
    val description: String,
    val detectedObjects: List<DetectedObject> = emptyList(),
    val extractedText: String? = null,
    val imageMetadata: ImageMetadata? = null,
    val confidence: Float = 0.0f,
    val processingTimeMs: Long = 0
)

/**
 * VLM Stream Output
 */
@Serializable
data class VLMStreamOutput(
    val partial: String,
    val isFinal: Boolean = false,
    val confidence: Float = 0.0f
)

/**
 * Detected Object
 */
@Serializable
data class DetectedObject(
    val label: String,
    val boundingBox: BoundingBox,
    val confidence: Float,
    val attributes: Map<String, String> = emptyMap()
)

/**
 * Bounding Box
 */
@Serializable
data class BoundingBox(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float
) {
    val centerX: Float get() = x + width / 2
    val centerY: Float get() = y + height / 2
    val area: Float get() = width * height
}

/**
 * Image Metadata
 */
@Serializable
data class ImageMetadata(
    val width: Int,
    val height: Int,
    val format: String,
    val colorSpace: String? = null,
    val orientation: Int = 1,
    val hasAlpha: Boolean = false
)

/**
 * Image size configuration for VLM models
 */
@Serializable
data class ImageSize(val width: Int, val height: Int) {
    companion object {
        val DEFAULT_336 = ImageSize(336, 336)  // Standard CLIP size
        val LARGE_672 = ImageSize(672, 672)    // High-resolution mode
        val CUSTOM = fun(size: Int) = ImageSize(size, size)
    }
}

/**
 * VLM optimization presets
 * Simple presets for mobile-first development
 */
enum class VLMPreset {
    SPEED,      // Prioritize fast inference (fewer tokens, lower temperature)
    BALANCED,   // Balance between speed and quality (default)
    QUALITY     // Prioritize output quality (more tokens, slightly higher temperature)
}

/**
 * Supported image formats for VLM processing
 */
enum class ImageFormat(val mimeType: String, val extension: String) {
    JPEG("image/jpeg", "jpg"),
    PNG("image/png", "png"),
    BMP("image/bmp", "bmp"),
    WEBP("image/webp", "webp");

    companion object {
        /** Get all supported format names */
        fun supportedFormats(): List<String> = values().map { it.name }

        /** Get format from mime type */
        fun fromMimeType(mimeType: String): ImageFormat? = values().firstOrNull { it.mimeType == mimeType }

        /** Get format from extension */
        fun fromExtension(ext: String): ImageFormat? = values().firstOrNull { it.extension.equals(ext, ignoreCase = true) }
    }
}

/**
 * VLM Configuration
 * Enhanced to support hardware optimization, matching LLMConfiguration pattern
 */
data class VLMConfiguration(
    // Model settings
    val modelId: String? = null,
    val modelPath: String? = null,
    val projectorPath: String? = null,  // Vision projector model (mmproj) for llama.cpp

    // Image settings
    val maxImageSize: Int = 336,  // Standard CLIP size (336x336)
    val imageSize: ImageSize = ImageSize.DEFAULT_336,
    val maxImages: Int = 1,  // Number of images to process simultaneously

    // Hardware settings (matching LLMConfiguration pattern)
    val nThreads: Int = 4,
    val nGpuLayers: Int = 0,  // Number of layers to offload to GPU
    val useMlock: Boolean = false,
    val useMmap: Boolean = true,

    // Generation settings
    val maxTokens: Int = 512,
    val temperature: Float = 0.1f,  // Lower temperature for more focused vision descriptions
    val topP: Float = 0.95f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,

    // Context settings
    val contextSize: Int = 2048,
    val batchSize: Int = 512,

    // Legacy settings (kept for compatibility)
    val confidenceThreshold: Float = 0.5f,
    val enableObjectDetection: Boolean = true,
    val enableOCR: Boolean = true,
    val supportedLanguages: List<String> = listOf("en"),

    // Optimization preset
    val preset: VLMPreset = VLMPreset.BALANCED
) : ComponentConfiguration {

    companion object {
        /**
         * Default configuration for mobile devices
         * Balanced settings suitable for most VLM models on mobile
         */
        val DEFAULT = VLMConfiguration(
            nThreads = 4,
            nGpuLayers = 0,
            maxTokens = 512,
            contextSize = 2048,
            temperature = 0.1f,
            preset = VLMPreset.BALANCED
        )
    }

    override fun validate() {
        require(maxImageSize > 0) { "Max image size must be positive" }
        require(confidenceThreshold >= 0f && confidenceThreshold <= 1f) {
            "Confidence threshold must be between 0 and 1"
        }
        require(nThreads > 0) { "nThreads must be positive" }
        require(nGpuLayers >= 0) { "nGpuLayers must be non-negative" }
        require(maxTokens > 0) { "maxTokens must be positive" }
        require(temperature >= 0f) { "temperature must be non-negative" }
        require(contextSize > 0) { "contextSize must be positive" }
        require(batchSize > 0) { "batchSize must be positive" }
        require(maxImages > 0) { "maxImages must be positive" }
    }
}

/**
 * VLM Service interface
 * Enhanced with full lifecycle management matching LLMService pattern
 */
interface VLMService {
    // MARK: - Lifecycle Methods

    /** Initialize the VLM service with optional model paths */
    suspend fun initialize(modelPath: String? = null, projectorPath: String? = null)

    /** Load a specific model */
    suspend fun loadModel(modelInfo: ModelInfo)

    /** Unload the currently loaded model from memory */
    suspend fun unloadModel()

    /** Cleanup resources */
    suspend fun cleanup()

    // MARK: - Core Image Processing

    /** Analyze an image with a prompt */
    suspend fun analyze(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): VLMOutput

    /** Generate text from image with options */
    suspend fun generateFromImage(
        image: ByteArray,
        prompt: String,
        modelId: String,
        options: GenerationOptions
    ): String

    /** Stream analysis results */
    fun analyzeStream(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): Flow<VLMStreamOutput>

    /** Process image with bytes directly (for llama.cpp integration) */
    suspend fun processImage(
        imageBytes: ByteArray,
        prompt: String
    ): VLMOutput

    /** Stream image processing results */
    fun processImageStream(
        imageBytes: ByteArray,
        prompt: String
    ): Flow<VLMStreamOutput>

    // MARK: - Batch Processing

    /** Process multiple images in batch */
    suspend fun processImageBatch(
        images: List<ByteArray>,
        prompts: List<String>
    ): List<VLMOutput>

    // MARK: - Control Methods

    /** Cancel current generation/processing */
    fun cancelCurrent()

    // MARK: - State Properties

    /** Check if service is ready */
    val isReady: Boolean

    /** Get current model identifier */
    val currentModel: String?

    /** Check if model is loaded */
    val isModelLoaded: Boolean

    // MARK: - Model Information

    /** Get model capabilities */
    fun getCapabilities(): VLMCapabilities

    /** Get model info */
    fun getModelInfo(): VLMModelInfo?
}

/**
 * VLM Model Capabilities
 */
data class VLMCapabilities(
    val supportsStreaming: Boolean = true,
    val supportsBatchProcessing: Boolean = true,
    val supportsMultipleImages: Boolean = false,
    val maxImageSize: ImageSize = ImageSize.DEFAULT_336,
    val supportedImageFormats: List<String> = listOf("JPEG", "PNG", "BMP"),
    val supportsObjectDetection: Boolean = false,
    val supportsOCR: Boolean = false
)

/**
 * VLM Model Information
 */
data class VLMModelInfo(
    val modelId: String,
    val name: String,
    val version: String? = null,
    val description: String? = null,
    val size: Long? = null,  // Model size in bytes
    val quantization: String? = null,  // e.g., "Q4_K_M", "F16"
    val architecture: String? = null,  // e.g., "vision-llm", "multimodal-transformer"
    val contextSize: Int = 2048,
    val capabilities: VLMCapabilities = VLMCapabilities()
)

/**
 * Adapter for ModuleRegistry providers
 * Wraps VLMServiceProvider to implement full VLMService interface
 */
class VLMServiceAdapter(
    private val provider: VLMServiceProvider
) : VLMService {
    private var _service: VLMService? = null

    override suspend fun initialize(modelPath: String?, projectorPath: String?) {
        // Service will be created through provider when needed
    }

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Provider handles model loading
    }

    override suspend fun unloadModel() {
        _service = null
    }

    override suspend fun cleanup() {
        _service = null
    }

    override suspend fun analyze(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): VLMOutput {
        return provider.analyze(image, prompt)
    }

    override suspend fun generateFromImage(
        image: ByteArray,
        prompt: String,
        modelId: String,
        options: GenerationOptions
    ): String {
        return provider.generateFromImage(image, prompt, options)
    }

    override fun analyzeStream(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): Flow<VLMStreamOutput> {
        return flow {
            val result = analyze(image, prompt, modelId)
            emit(VLMStreamOutput(result.description, true, result.confidence))
        }
    }

    override suspend fun processImage(
        imageBytes: ByteArray,
        prompt: String
    ): VLMOutput {
        return analyze(imageBytes, prompt, "default")
    }

    override fun processImageStream(
        imageBytes: ByteArray,
        prompt: String
    ): Flow<VLMStreamOutput> {
        return analyzeStream(imageBytes, prompt, "default")
    }

    override suspend fun processImageBatch(
        images: List<ByteArray>,
        prompts: List<String>
    ): List<VLMOutput> {
        return images.mapIndexed { index, image ->
            analyze(image, prompts.getOrNull(index) ?: "Describe this image", "default")
        }
    }

    override fun cancelCurrent() {
        // Provider handles cancellation
    }

    override val isReady: Boolean get() = _service != null
    override val currentModel: String? get() = null
    override val isModelLoaded: Boolean get() = false

    override fun getCapabilities(): VLMCapabilities {
        return VLMCapabilities()
    }

    override fun getModelInfo(): VLMModelInfo? {
        return null
    }
}

/**
 * Default VLM service implementation (stub)
 * Throws errors to indicate that a real provider must be registered
 */
class DefaultVLMService : VLMService {
    private var _isReady = false
    private var _currentModel: String? = null

    override suspend fun initialize(modelPath: String?, projectorPath: String?) {
        throw com.runanywhere.sdk.data.models.VLMServiceError.NoProviderAvailable
    }

    override suspend fun loadModel(modelInfo: ModelInfo) {
        throw com.runanywhere.sdk.data.models.VLMServiceError.NoProviderAvailable
    }

    override suspend fun unloadModel() {
        _isReady = false
        _currentModel = null
    }

    override suspend fun cleanup() {
        _isReady = false
        _currentModel = null
    }

    override suspend fun analyze(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): VLMOutput {
        return VLMOutput(
            description = "No VLM provider available",
            detectedObjects = emptyList(),
            extractedText = null,
            imageMetadata = null,
            confidence = 0.0f,
            processingTimeMs = 0
        )
    }

    override suspend fun generateFromImage(
        image: ByteArray,
        prompt: String,
        modelId: String,
        options: GenerationOptions
    ): String {
        return "No VLM provider available"
    }

    override fun analyzeStream(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): Flow<VLMStreamOutput> {
        return flow {
            emit(VLMStreamOutput("No VLM provider available", true, 0.0f))
        }
    }

    override suspend fun processImage(
        imageBytes: ByteArray,
        prompt: String
    ): VLMOutput {
        return analyze(imageBytes, prompt, "default")
    }

    override fun processImageStream(
        imageBytes: ByteArray,
        prompt: String
    ): Flow<VLMStreamOutput> {
        return analyzeStream(imageBytes, prompt, "default")
    }

    override suspend fun processImageBatch(
        images: List<ByteArray>,
        prompts: List<String>
    ): List<VLMOutput> {
        return images.mapIndexed { index, image ->
            analyze(image, prompts.getOrNull(index) ?: "Describe this image", "default")
        }
    }

    override fun cancelCurrent() {
        // No-op for stub
    }

    override val isReady: Boolean get() = _isReady
    override val currentModel: String? get() = _currentModel
    override val isModelLoaded: Boolean get() = false

    override fun getCapabilities(): VLMCapabilities {
        return VLMCapabilities(
            supportsStreaming = false,
            supportsBatchProcessing = false,
            supportsMultipleImages = false
        )
    }

    override fun getModelInfo(): VLMModelInfo? {
        return null
    }
}
