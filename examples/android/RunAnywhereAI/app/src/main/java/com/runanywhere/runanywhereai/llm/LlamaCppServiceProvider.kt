package com.runanywhere.runanywhereai.llm

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.llm.llamacpp.LLamaAndroid
import com.runanywhere.sdk.llm.llamacpp.LlamaCppService
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import com.runanywhere.sdk.models.enums.LLMFramework
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Service Provider for Llama.cpp (llama-cpp) framework
 * Matches iOS LLMSwiftServiceProvider pattern
 *
 * This registers the llama.cpp framework capability with the SDK's ModuleRegistry,
 * making it available for model management and text generation.
 */
object LlamaCppServiceProvider : LLMServiceProvider {

    private val logger = SDKLogger("LlamaCppServiceProvider")

    override val name: String = "Llama.cpp (llama-cpp)"

    override val framework: LLMFramework = LLMFramework.LLAMA_CPP

    override val supportedFeatures: Set<String> = setOf(
        "text-generation",
        "streaming",
        "quantization",
        "gguf-format"
    )

    init {
        // Force native library loading by accessing LLamaAndroid instance
        try {
            LLamaAndroid.instance()
            logger.info("✅ llama.cpp native library loaded successfully")
        } catch (e: Exception) {
            logger.error("❌ llama.cpp native library failed to load", e)
        }
    }

    /**
     * Register this provider with ModuleRegistry
     * Call this in your Application.onCreate() after SDK initialization
     */
    fun register() {
        ModuleRegistry.registerLLM(this)
    }

    override fun canHandle(modelId: String?): Boolean {
        // For now, accept all models since this is the only LLM provider
        // Model compatibility is validated in validateModelCompatibility()
        return true

        // TODO: Re-enable this check once we support multiple providers
        // Accept nil/empty or default
        // if (modelId.isNullOrEmpty() || modelId == "default") return true
        //
        // Check for supported file extensions
        // val supportedExtensions = listOf(".gguf", ".ggml", ".bin")
        // val lowercasedId = modelId.lowercase()
        // return supportedExtensions.any { lowercasedId.endsWith(it) }
    }

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        logger.info("Creating LlamaCppService with configuration: ${configuration.modelId}")

        try {
            // Check if native library is available
            LLamaAndroid.instance()
        } catch (e: Exception) {
            throw IllegalStateException("Cannot create LlamaCppService: Native library not loaded", e)
        }

        return LlamaCppService(configuration)
    }

    override fun validateModelCompatibility(model: ModelInfo): com.runanywhere.sdk.components.llm.ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        // Check if model format is supported
        if (model.format != com.runanywhere.sdk.models.enums.ModelFormat.GGUF &&
            model.format != com.runanywhere.sdk.models.enums.ModelFormat.GGML) {
            return com.runanywhere.sdk.components.llm.ModelCompatibilityResult(
                isCompatible = false,
                details = "Llama.cpp only supports GGUF and GGML formats",
                memoryRequired = 0L,
                warnings = listOf("Unsupported model format: ${model.format}")
            )
        }

        // Check memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available ($memoryRequired bytes required, $availableMemory bytes available)")
        }

        return com.runanywhere.sdk.components.llm.ModelCompatibilityResult(
            isCompatible = true,
            details = "Model is compatible with Llama.cpp",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo {
        // Delegate to SDK's download service
        return withContext(Dispatchers.IO) {
            // The actual download is handled by RunAnywhere.downloadModel()
            // This is just a placeholder
            throw UnsupportedOperationException("Use RunAnywhere.downloadModel() instead")
        }
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        // Use model's declared memory requirement or estimate from download size
        return model.memoryRequired ?: model.downloadSize ?: 1_000_000_000L
    }

    override fun getOptimalConfiguration(model: ModelInfo): com.runanywhere.sdk.components.llm.HardwareConfiguration {
        return com.runanywhere.sdk.components.llm.HardwareConfiguration(
            preferGPU = false,  // CPU-only for now
            minMemoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt(),
            recommendedThreads = Runtime.getRuntime().availableProcessors()
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId,
            category = com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE,
            format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF,
            downloadURL = null,
            localPath = null,
            downloadSize = null,
            memoryRequired = null,
            compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
            preferredFramework = LLMFramework.LLAMA_CPP,
            contextLength = 4096
        )
    }

    /**
     * Get available system memory (helper method, not from interface)
     */
    private fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }
}
