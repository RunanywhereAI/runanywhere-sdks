package com.runanywhere.sdk.components.llm

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.models.enums.LLMFramework
import kotlinx.coroutines.flow.Flow

/**
 * Protocol for Language Model services - unified interface matching iOS LLMService protocol
 * This interface combines simple text generation with structured message-based chat support
 */
interface LLMService {
    // Core initialization and lifecycle
    /** Initialize the LLM service with optional model path */
    suspend fun initialize(modelPath: String?)

    /** Load a specific model */
    suspend fun loadModel(modelInfo: ModelInfo)

    /** Cleanup resources */
    suspend fun cleanup()

    // Simple text generation (for backward compatibility and simple use cases)
    /** Generate text from prompt - automatically applies chat templates */
    suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String

    /** Stream generation token by token - automatically applies chat templates */
    suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )

    // Structured message-based generation (for proper chat applications)
    /** Process structured LLM input with messages and roles */
    suspend fun process(input: LLMInput): LLMOutput

    /** Stream generation with structured input/output */
    fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>

    // Utility methods
    /** Cancel current generation */
    fun cancelCurrent()

    /** Get token count for text */
    fun getTokenCount(text: String): Int

    /** Check if prompt fits within context window */
    fun fitsInContext(prompt: String, maxTokens: Int): Boolean

    // State properties
    /** Check if service is ready */
    val isReady: Boolean

    /** Get current model identifier */
    val currentModel: String?
}

/**
 * Protocol for registering external LLM implementations - enhanced from iOS LLMServiceProvider
 */
interface LLMServiceProvider {
    /** Create an LLM service for the given configuration */
    suspend fun createLLMService(configuration: LLMConfiguration): LLMService

    /** Check if this provider can handle the given model */
    fun canHandle(modelId: String?): Boolean

    /** Provider name for identification */
    val name: String

    /** Framework this provider supports */
    val framework: LLMFramework

    /** Supported features */
    val supportedFeatures: Set<String>


    /** Check model compatibility with detailed validation */
    fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult

    /** Download model with progress tracking */
    suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit = {}
    ): ModelInfo

    /** Estimate memory requirements for model */
    fun estimateMemoryRequirements(model: ModelInfo): Long

    /** Get optimal hardware configuration for model */
    fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration

    /** Create ModelInfo from model ID */
    fun createModelInfo(modelId: String): ModelInfo
}

/**
 * Model compatibility check result
 */
data class ModelCompatibilityResult(
    /** Whether the model is compatible */
    val isCompatible: Boolean,

    /** Detailed compatibility information */
    val details: String,

    /** Required memory in bytes */
    val memoryRequired: Long = 0L,

    /** Recommended hardware configuration */
    val recommendedConfiguration: HardwareConfiguration? = null,

    /** Any warnings about compatibility */
    val warnings: List<String> = emptyList()
)

/**
 * Base LLM Service Provider implementation
 */
abstract class BaseLLMServiceProvider : LLMServiceProvider {

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false
        // Simple check based on model ID patterns
        return true
    }

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        // Check memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available")
        }

        return ModelCompatibilityResult(
            isCompatible = true,
            details = "Model is compatible with ${framework.displayName}",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        // Simple estimation based on model size
        return model.memoryRequired ?: model.downloadSize ?: 8_000_000_000L
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return HardwareConfiguration(
            preferGPU = true,
            minMemoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt(),
            recommendedThreads = 4
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return createModelInfoImpl(modelId)
    }

    override suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): ModelInfo {
        // Default implementation - subclasses should override for actual download
        onProgress(0.0f)

        // Simulate download progress
        for (progress in 0..100 step 10) {
            onProgress(progress / 100f)
            kotlinx.coroutines.delay(100)
        }

        return createModelInfoImpl(modelId)
    }

    /** Create a basic ModelInfo from model ID - override for more sophisticated creation */
    protected open fun createModelInfoImpl(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId,
            category = com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE,
            format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF,
            downloadURL = null,
            localPath = null,
            downloadSize = null,
            memoryRequired = null,
            compatibleFrameworks = listOf(com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP),
            preferredFramework = com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = null
        )
    }

    /** Get available system memory - platform-specific */
    protected abstract fun getAvailableSystemMemory(): Long
}

// LlamaCppServiceProvider and LlamaCppService moved to :modules:runanywhere-llm-llamacpp module
// This keeps the core SDK free of platform-specific implementations
