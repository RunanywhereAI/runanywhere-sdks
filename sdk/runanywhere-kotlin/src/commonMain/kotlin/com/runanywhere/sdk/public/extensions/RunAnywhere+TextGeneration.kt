package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.capabilities.llm.LLMCapability
import com.runanywhere.sdk.capabilities.llm.LLMGenerationOptions
import com.runanywhere.sdk.capabilities.llm.LLMGenerationResult
import com.runanywhere.sdk.capabilities.llm.LLMStreamingResult
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.flow.Flow

// ═══════════════════════════════════════════════════════════════════════════
// RunAnywhere Text Generation Extensions
// LLM operations aligned with iOS RunAnywhere+TextGeneration.swift
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Model Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Load an LLM model by ID
 *
 * @param modelId The model identifier
 * @throws SDKError if loading fails or no provider is available
 */
suspend fun RunAnywhere.loadModel(modelId: String) {
    requireInitialized()
    ensureServicesReady()

    val capability = llmCapability
        ?: throw SDKError.ComponentNotInitialized("LLM capability not available")

    capability.loadModel(modelId)
}

/**
 * Unload the currently loaded LLM model
 */
suspend fun RunAnywhere.unloadModel() {
    requireInitialized()

    val capability = llmCapability ?: return
    capability.unload()
}

/**
 * Check if an LLM model is currently loaded
 */
val RunAnywhere.isModelLoaded: Boolean
    get() = llmCapability?.isModelLoaded ?: false

/**
 * Get the currently loaded LLM model ID
 */
val RunAnywhere.currentLLMModelId: String?
    get() = llmCapability?.currentModelId

/**
 * Check if the loaded model supports streaming
 */
val RunAnywhere.supportsLLMStreaming: Boolean
    get() = llmCapability?.supportsStreaming ?: false

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Generation API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Simple chat method - generate a response to a prompt
 *
 * @param prompt The input prompt
 * @return Generated text
 */
suspend fun RunAnywhere.chat(prompt: String): String {
    requireInitialized()
    ensureServicesReady()

    val capability = llmCapability
        ?: throw SDKError.ComponentNotReady("LLM capability not available. Call loadModel() first.")

    val result = capability.generate(prompt, LLMGenerationOptions())
    return result.text
}

/**
 * Generate text with full options
 *
 * @param prompt The input prompt
 * @param options Generation options
 * @return LLMGenerationResult with generated text and metrics
 */
suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions()
): LLMGenerationResult {
    requireInitialized()
    ensureServicesReady()

    val capability = llmCapability
        ?: throw SDKError.ComponentNotReady("LLM capability not available. Call loadModel() first.")

    return capability.generate(prompt, options)
}

/**
 * Stream text generation
 *
 * @param prompt The input prompt
 * @param options Generation options
 * @return LLMStreamingResult with token stream and metrics accessor
 */
suspend fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions()
): LLMStreamingResult {
    requireInitialized()
    ensureServicesReady()

    val capability = llmCapability
        ?: throw SDKError.ComponentNotReady("LLM capability not available. Call loadModel() first.")

    return capability.generateStream(prompt, options)
}

/**
 * Cancel current generation
 */
fun RunAnywhere.cancelGeneration() {
    llmCapability?.cancel()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Convenience Methods
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Get the currently loaded model info (if any)
 * Note: This is a suspend function because model lookup may involve I/O
 */
suspend fun RunAnywhere.getCurrentLLMModel(): com.runanywhere.sdk.models.ModelInfo? {
    val modelId = currentLLMModelId ?: return null
    return try {
        serviceContainer.modelInfoService.getModel(modelId)
    } catch (e: Exception) {
        null
    }
}
