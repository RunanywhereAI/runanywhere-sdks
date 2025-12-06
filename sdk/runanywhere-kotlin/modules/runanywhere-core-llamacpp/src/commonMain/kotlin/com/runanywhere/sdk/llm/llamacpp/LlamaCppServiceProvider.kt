package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.components.llm.ModelCompatibilityResult
import com.runanywhere.sdk.components.llm.HardwareConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * LlamaCpp provider for Language Model services via RunAnywhere Core.
 *
 * This provider wraps runanywhere-core's LlamaCPP backend which includes
 * proper chat template support for all models (Qwen, LFM2, Llama, etc.)
 *
 * Usage:
 * ```kotlin
 * import com.runanywhere.sdk.llm.llamacpp.LlamaCppServiceProvider
 *
 * // In your Application.onCreate():
 * LlamaCppServiceProvider.register()
 * ```
 */
object LlamaCppServiceProvider : LLMServiceProvider {
    private val logger = SDKLogger("LlamaCppServiceProvider")

    /**
     * Simple registration - just call this in your app
     */
    fun register() {
        ModuleRegistry.shared.registerLLM(this)
        logger.info("LlamaCppServiceProvider registered (RunAnywhere Core backend)")
    }

    // MARK: - LLMServiceProvider Protocol

    override val name: String = "LlamaCpp (RunAnywhere Core)"

    override val framework: LLMFramework = LLMFramework.LLAMA_CPP

    override val supportedFeatures: Set<String> = setOf(
        "text-generation",
        "streaming",
        "quantization",
        "gguf-format",
        "chat-templates"
    )

    override fun canHandle(modelId: String?): Boolean {
        // LlamaCpp is the primary LLM provider and handles all GGUF/GGML models
        return true
    }

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        logger.info("Creating LlamaCpp service (RunAnywhere Core backend)")

        // Create the service
        val service = LlamaCppService(configuration)

        // Initialize with model path if provided
        val modelId = configuration.modelId
        if (!modelId.isNullOrEmpty() && modelId != "default") {
            logger.info("Initializing with model: $modelId")
            service.initialize(modelId)
        } else {
            logger.info("Using default model - service will be initialized later")
        }

        logger.info("LlamaCpp service created successfully")
        return service
    }

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        // Check if model format is supported
        val modelFormat = model.format
        if (modelFormat != ModelFormat.GGUF &&
            modelFormat != ModelFormat.GGML
        ) {
            return ModelCompatibilityResult(
                isCompatible = false,
                details = "Llama.cpp only supports GGUF and GGML formats",
                memoryRequired = 0L,
                warnings = listOf("Unsupported model format: $modelFormat")
            )
        }

        // Check memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available ($memoryRequired bytes required, $availableMemory bytes available)")
        }

        return ModelCompatibilityResult(
            isCompatible = true,
            details = "Model is compatible with Llama.cpp (RunAnywhere Core)",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo {
        throw UnsupportedOperationException("Use RunAnywhere.downloadModel() instead")
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        return model.memoryRequired ?: model.downloadSize ?: 1_000_000_000L
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return HardwareConfiguration(
            preferGPU = false, // CPU-only for now
            minMemoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt(),
            recommendedThreads = Runtime.getRuntime().availableProcessors()
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId,
            category = ModelCategory.LANGUAGE,
            format = ModelFormat.GGUF,
            downloadURL = null,
            localPath = null,
            downloadSize = null,
            memoryRequired = null,
            compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
            preferredFramework = LLMFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = null
        )
    }

    private fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }
}
