package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.Message
import com.runanywhere.sdk.models.MessageRole
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * LLM Capability - Public API wrapper for Language Model operations
 *
 * Aligned with iOS LLMCapability pattern:
 * - Model lifecycle management (loadModel, unload, isModelLoaded)
 * - Generation API (generate, generateStream)
 * - Cancellation (cancel)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps LLMComponent and provides the interface expected by
 * the public RunAnywhere+TextGeneration.kt extension functions.
 */
class LLMCapability internal constructor(
    private val getComponent: () -> LLMComponent,
) {
    private val logger = SDKLogger("LLMCapability")

    /**
     * Check if an LLM model is currently loaded
     */
    val isModelLoaded: Boolean
        get() = getComponent().isModelLoaded

    /**
     * Get the currently loaded model ID
     */
    val currentModelId: String?
        get() = getComponent().loadedModelId

    /**
     * Check if streaming is supported
     */
    val supportsStreaming: Boolean
        get() = true // LLMComponent always supports streaming via Flow

    // ============================================================================
    // MARK: - Model Lifecycle (iOS ModelLoadableCapability pattern)
    // ============================================================================

    /**
     * Load an LLM model by ID
     *
     * @param modelId The model identifier
     * @throws SDKError if loading fails or no provider is available
     */
    suspend fun loadModel(modelId: String) {
        logger.info("Loading LLM model: $modelId")

        // Check if provider is available
        if (!ModuleRegistry.hasLLM) {
            throw SDKError.ComponentNotInitialized(
                "No LLM service provider registered. Add llama.cpp or another LLM module as a dependency.",
            )
        }

        try {
            // Initialize the component (which handles model loading internally)
            val component = getComponent()
            component.initialize()

            logger.info("✅ LLM model loaded: $modelId")
        } catch (e: Exception) {
            logger.error("Failed to load LLM model: $modelId", e)
            throw SDKError.ModelLoadingFailed("Failed to load LLM model: ${e.message}")
        }
    }

    /**
     * Unload the currently loaded LLM model
     */
    suspend fun unload() {
        logger.info("Unloading LLM model")

        try {
            getComponent().unloadModel()
            logger.info("✅ LLM model unloaded")
        } catch (e: Exception) {
            logger.error("Failed to unload LLM model", e)
            throw e
        }
    }

    // ============================================================================
    // MARK: - Generation API
    // ============================================================================

    /**
     * Generate text (non-streaming)
     *
     * @param prompt The input prompt
     * @param options Generation options
     * @return LLMGenerationResult with generated text and metrics
     */
    suspend fun generate(
        prompt: String,
        options: LLMGenerationOptions,
    ): LLMGenerationResult {
        ensureModelLoaded()

        val component = getComponent()

        // Build input with options
        val input =
            LLMInput(
                messages = listOf(Message(role = MessageRole.USER, content = prompt)),
                systemPrompt = options.systemPrompt,
                options =
                    LLMGenerationOptions(
                        maxTokens = options.maxTokens,
                        temperature = options.temperature,
                        topP = options.topP,
                        topK = options.topK,
                        stopSequences = options.stopSequences,
                        streamingEnabled = false,
                        enableThinking = options.enableThinking,
                        maxThinkingTokens = options.maxThinkingTokens,
                    ),
            )

        val output = component.process(input)

        return output.toLLMGenerationResult(enableThinking = options.enableThinking)
    }

    /**
     * Stream text generation
     *
     * @param prompt The input prompt
     * @param options Generation options
     * @return LLMStreamingResult with token stream and metrics accessor
     */
    suspend fun generateStream(
        prompt: String,
        options: LLMGenerationOptions,
    ): LLMStreamingResult {
        ensureModelLoaded()

        val component = getComponent()
        val enableThinking = options.enableThinking

        // Build input with options
        val input =
            LLMInput(
                messages = listOf(Message(role = MessageRole.USER, content = prompt)),
                systemPrompt = options.systemPrompt,
                options =
                    LLMGenerationOptions(
                        maxTokens = options.maxTokens,
                        temperature = options.temperature,
                        topP = options.topP,
                        topK = options.topK,
                        stopSequences = options.stopSequences,
                        streamingEnabled = true,
                        enableThinking = options.enableThinking,
                        maxThinkingTokens = options.maxThinkingTokens,
                    ),
            )

        // Get streaming flow from component
        val tokenFlow =
            component.streamProcess(input).map { chunk ->
                chunk.text
            }

        // Create result with metrics placeholder
        // In a full implementation, we'd track metrics during streaming
        return LLMStreamingResult(
            stream = tokenFlow,
            getMetrics = {
                // Generate after streaming completes - this is a simplified version
                // In production, we'd accumulate metrics during streaming
                val result = component.process(input)
                result.toLLMGenerationResult(enableThinking = enableThinking)
            },
        )
    }

    /**
     * Cancel current generation
     */
    fun cancel() {
        try {
            getComponent().cancelCurrent()
            logger.info("Generation cancelled")
        } catch (e: Exception) {
            logger.debug("Cancel called but no generation in progress")
        }
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureModelLoaded() {
        if (!isModelLoaded) {
            throw SDKError.ComponentNotReady("LLM model not loaded. Call loadModel() first.")
        }
    }

    private fun LLMOutput.toLLMGenerationResult(enableThinking: Boolean = false): LLMGenerationResult {
        // Extract thinking content if enabled
        val (responseText, thinkingContent, thinkingTokens) =
            if (enableThinking) {
                val extraction = ThinkingTagPattern.autoExtract(this.text)
                Triple(extraction.responseContent, extraction.thinkingContent, extraction.thinkingTokens)
            } else {
                Triple(this.text, null, null)
            }

        return LLMGenerationResult(
            text = responseText,
            tokensUsed = this.tokenUsage.totalTokens,
            latencyMs = (this.metadata.generationTime ?: 0L).toDouble(),
            performanceMetrics =
                LLMPerformanceMetrics(
                    tokensPerSecond = this.metadata.tokensPerSecond ?: 0.0,
                    timeToFirstTokenMs = null, // Not tracked in component
                    inferenceTimeMs = (this.metadata.generationTime ?: 0L).toDouble(),
                ),
            thinkingTokensUsed = thinkingTokens,
            thinkingContent = thinkingContent,
        )
    }
}

// ============================================================================
// MARK: - Internal Types (Used by Capability)
// ============================================================================

// LLMGenerationOptions is now defined in com.runanywhere.sdk.models.LLMGenerationOptions
// to avoid duplication and match iOS SDK structure.

/**
 * Performance metrics for generation
 */
data class LLMPerformanceMetrics(
    /** Tokens per second */
    val tokensPerSecond: Double,
    /** Time to first token in milliseconds */
    val timeToFirstTokenMs: Double?,
    /** Total inference time in milliseconds */
    val inferenceTimeMs: Double,
)

/**
 * LLM generation result with full metrics
 */
data class LLMGenerationResult(
    /** Generated text */
    val text: String,
    /** Total tokens used (input + output) */
    val tokensUsed: Int,
    /** Total latency in milliseconds */
    val latencyMs: Double,
    /** Performance metrics */
    val performanceMetrics: LLMPerformanceMetrics,
    /** Thinking tokens used (for reasoning models) */
    val thinkingTokensUsed: Int? = null,
    /** Thinking content (for reasoning models) */
    val thinkingContent: String? = null,
)

/**
 * Streaming generation result
 * Contains both the token stream and a way to get final metrics.
 */
data class LLMStreamingResult(
    /** Flow of generated tokens */
    val stream: Flow<String>,
    /** Suspend function to get final metrics after streaming completes */
    val getMetrics: suspend () -> LLMGenerationResult,
)
