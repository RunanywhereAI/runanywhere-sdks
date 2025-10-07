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
 * VLM Configuration
 */
data class VLMConfiguration(
    val modelId: String? = null,
    val maxImageSize: Int = 1024,
    val confidenceThreshold: Float = 0.5f,
    val enableObjectDetection: Boolean = true,
    val enableOCR: Boolean = true,
    val supportedLanguages: List<String> = listOf("en")
) : ComponentConfiguration {
    override fun validate() {
        require(maxImageSize > 0) { "Max image size must be positive" }
        require(confidenceThreshold >= 0f && confidenceThreshold <= 1f) {
            "Confidence threshold must be between 0 and 1"
        }
    }
}

/**
 * VLM Service interface
 */
interface VLMService {
    suspend fun analyze(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): VLMOutput

    suspend fun generateFromImage(
        image: ByteArray,
        prompt: String,
        modelId: String,
        options: GenerationOptions
    ): String

    fun analyzeStream(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): Flow<VLMStreamOutput>

    suspend fun loadModel(modelInfo: ModelInfo)
    fun cancelCurrent()
}

/**
 * Adapter for ModuleRegistry providers
 */
class VLMServiceAdapter(
    private val provider: VLMServiceProvider
) : VLMService {
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

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Provider handles model loading
    }

    override fun cancelCurrent() {
        // Provider handles cancellation
    }
}

/**
 * Default VLM service implementation
 */
class DefaultVLMService : VLMService {
    override suspend fun analyze(
        image: ByteArray,
        prompt: String,
        modelId: String
    ): VLMOutput {
        // Default implementation - would use actual VLM model
        return VLMOutput(
            description = "Image analysis not available",
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
        return "Generated text from image: $prompt"
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

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Load model implementation
    }

    override fun cancelCurrent() {
        // Cancel implementation
    }
}
