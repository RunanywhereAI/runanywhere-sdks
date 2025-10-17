package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.ModelCompatibilityResult
import com.runanywhere.sdk.components.llm.HardwareConfiguration
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework

/**
 * llama.cpp LLM service provider implementation
 * Provides on-device LLM capabilities using llama.cpp
 */
class LlamaCppProvider : LLMServiceProvider {

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        return LlamaCppService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        // Handle GGUF/GGML models and llama-based models
        val modelIdLower = modelId.lowercase()
        return modelIdLower.contains("llama") ||
               modelIdLower.endsWith(".gguf") ||
               modelIdLower.endsWith(".ggml") ||
               modelIdLower.contains("mistral") ||
               modelIdLower.contains("mixtral") ||
               modelIdLower.contains("phi") ||
               modelIdLower.contains("gemma") ||
               modelIdLower.contains("qwen") ||
               modelIdLower.contains("codellama")
    }

    override val name: String = "LlamaCpp"

    override val framework: LLMFramework = LLMFramework.LLAMA_CPP

    override val supportedFeatures: Set<String> = setOf(
        "streaming",
        "context-window-8k",
        "context-window-32k",
        "context-window-128k",
        "gpu-acceleration",
        "quantization",
        "grammar-sampling",
        "rope-scaling",
        "flash-attention",
        "continuous-batching"
    )

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        // Check if it's a supported format
        val isCompatible = when {
            model.format.toString().contains("GGUF", ignoreCase = true) -> true
            model.format.toString().contains("GGML", ignoreCase = true) -> true
            else -> {
                warnings.add("Model format ${model.format} may not be fully supported")
                false
            }
        }

        // Check memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available (${memoryRequired / 1024 / 1024}MB required)")
        }

        return ModelCompatibilityResult(
            isCompatible = isCompatible,
            details = "Model ${model.name} compatibility check for llama.cpp framework",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): ModelInfo {
        // For now, just create a basic ModelInfo
        // Real implementation would download from model registry
        onProgress(1.0f)
        return createModelInfo(modelId)
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        // Base memory estimation
        val modelSize = model.downloadSize ?: 8_000_000_000L // 8GB default
        val contextMemory = (model.contextLength ?: 2048) * 4L * 1024 // 4 bytes per token
        return modelSize + contextMemory
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val memoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt()

        return HardwareConfiguration(
            preferGPU = true,
            minMemoryMB = memoryMB,
            recommendedThreads = minOf(Runtime.getRuntime().availableProcessors(), 8),
            useMmap = true,
            lockMemory = memoryMB < 4096 // Only lock memory for smaller models
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId.split("/").lastOrNull() ?: modelId,
            category = com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE,
            format = if (modelId.endsWith(".gguf")) {
                com.runanywhere.sdk.models.enums.ModelFormat.GGUF
            } else {
                com.runanywhere.sdk.models.enums.ModelFormat.GGML
            },
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
        // Platform-specific implementation would go here
        // For now, return a conservative estimate
        return Runtime.getRuntime().maxMemory()
    }
}
