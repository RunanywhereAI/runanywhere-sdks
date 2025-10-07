package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.LLMServiceProvider
import com.runanywhere.sdk.generation.GenerationOptions
import com.runanywhere.sdk.generation.GenerationResult
import kotlinx.coroutines.flow.Flow

/**
 * llama.cpp LLM service provider implementation
 * Provides on-device LLM capabilities using llama.cpp
 */
class LlamaCppProvider : LLMServiceProvider {

    private var currentService: LlamaCppService? = null

    override suspend fun createLLMService(modelPath: String): LlamaCppService {
        val service = LlamaCppService()
        service.initialize(modelPath)
        currentService = service
        return service
    }

    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        val service = currentService ?: throw IllegalStateException("LlamaCpp service not initialized")
        return service.generate(prompt, options)
    }

    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> {
        val service = currentService ?: throw IllegalStateException("LlamaCpp service not initialized")
        return service.generateStream(prompt, options)
    }

    override fun canHandle(modelId: String): Boolean {
        // Handle GGUF/GGML models and llama-based models
        return modelId.contains("llama") ||
               modelId.endsWith(".gguf") ||
               modelId.endsWith(".ggml") ||
               modelId.contains("mistral") ||
               modelId.contains("mixtral") ||
               modelId.contains("phi")
    }

    override val name: String = "llama.cpp"

    override val priority: Int = 100 // High priority for on-device inference

    override val supportedFeatures: Set<String> = setOf(
        "streaming",
        "context-window-8k",
        "context-window-32k",
        "gpu-acceleration",
        "quantization",
        "grammar-sampling"
    )

    suspend fun cleanup() {
        currentService?.cleanup()
        currentService = null
    }
}

/**
 * LlamaCpp service interface - platform implementations will provide actual functionality
 */
expect class LlamaCppService() {
    suspend fun initialize(modelPath: String)
    suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult
    fun generateStream(prompt: String, options: GenerationOptions): Flow<String>
    suspend fun cleanup()
}
