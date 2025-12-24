package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.CapabilityError
import com.runanywhere.sdk.core.capabilities.CapabilityResourceType
import com.runanywhere.sdk.core.capabilities.ManagedLifecycle
import com.runanywhere.sdk.core.capabilities.ModelLifecycleManager
import com.runanywhere.sdk.core.capabilities.ModelLoadableCapability
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.Message
import com.runanywhere.sdk.models.MessageRole
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * LLM Capability - Actor-like class for Language Model operations
 *
 * Aligned EXACTLY with iOS LLMCapability pattern:
 * - Uses ManagedLifecycle<LLMService> directly for model lifecycle
 * - No intermediate Component layer
 * - Model lifecycle management (loadModel, unload, isModelLoaded)
 * - Generation API (generate, generateStream)
 * - Cancellation (cancel)
 * - Analytics tracking via GenerationAnalyticsService
 */
class LLMCapability internal constructor(
    private val analyticsService: GenerationAnalyticsService = GenerationAnalyticsService(),
) : ModelLoadableCapability<LLMConfiguration, LLMService> {
    private val logger = SDKLogger("LLMCapability")

    // Managed lifecycle with integrated event tracking (matches iOS)
    private val managedLifecycle: ManagedLifecycle<LLMService> = createLLMManagedLifecycle()

    // Current configuration
    private var config: LLMConfiguration? = null

    // ============================================================================
    // MARK: - Configuration (Capability Protocol)
    // ============================================================================

    override fun configure(config: LLMConfiguration) {
        this.config = config
        // Configure lifecycle asynchronously - matches iOS pattern
    }

    // ============================================================================
    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
    // ============================================================================

    /**
     * Whether a model is currently loaded
     */
    override val isModelLoaded: Boolean
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.isLoaded() } }.getOrElse { false }

    /**
     * Get the currently loaded model ID
     */
    override val currentModelId: String?
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.currentResourceId() } }.getOrNull()

    /**
     * Whether streaming is supported (LLM always supports streaming via Flow)
     */
    val supportsStreaming: Boolean
        get() = true

    /**
     * Load an LLM model by ID
     *
     * @param modelId The model identifier
     * @throws SDKError if loading fails or no provider is available
     */
    override suspend fun loadModel(modelId: String) {
        logger.info("Loading LLM model: $modelId")

        // Check if provider is available
        if (!ModuleRegistry.hasLLM) {
            throw SDKError.ComponentNotInitialized(
                "No LLM service provider registered. Add llama.cpp or another LLM module as a dependency.",
            )
        }

        try {
            managedLifecycle.load(modelId)
            logger.info("✅ LLM model loaded: $modelId")
        } catch (e: CapabilityError) {
            logger.error("Failed to load LLM model: $modelId", e)
            throw SDKError.ModelLoadingFailed("Failed to load LLM model: ${e.message}")
        } catch (e: Exception) {
            logger.error("Failed to load LLM model: $modelId", e)
            throw SDKError.ModelLoadingFailed("Failed to load LLM model: ${e.message}")
        }
    }

    /**
     * Unload the currently loaded LLM model
     */
    override suspend fun unload() {
        logger.info("Unloading LLM model")
        try {
            managedLifecycle.unload()
            logger.info("✅ LLM model unloaded")
        } catch (e: Exception) {
            logger.error("Failed to unload LLM model", e)
            throw e
        }
    }

    /**
     * Cleanup all resources
     */
    override suspend fun cleanup() {
        managedLifecycle.reset()
    }

    /**
     * Cancel the current generation operation
     * Note: Best-effort cancellation; some backends may not support mid-generation cancellation
     */
    fun cancel() {
        logger.info("Generation cancellation requested")
        // Current LLM service implementations don't expose cancel
        // This is tracked at the capability level
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
        val service = managedLifecycle.requireService()
        val modelId = managedLifecycle.resourceIdOrUnknown()

        logger.info("Generating with model: $modelId (non-streaming)")

        // Apply configuration defaults if not specified in options
        val effectiveOptions = mergeOptions(options)

        val startTime = currentTimeMillis()

        // Determine framework from configuration or default
        val framework = config?.framework ?: InferenceFramework.LLAMA_CPP

        // Build prompt with system prompt
        val fullPrompt = buildPrompt(
            messages = listOf(Message(role = MessageRole.USER, content = prompt)),
            systemPrompt = effectiveOptions.systemPrompt ?: config?.effectiveSystemPrompt,
        )

        // Rough token estimation (~4 chars per token)
        val inputTokens = maxOf(1, fullPrompt.length / 4)

        // Start generation tracking (non-streaming mode)
        val generationId = analyticsService.startGeneration(modelId, framework)

        val generatedText: String
        try {
            generatedText = service.generate(fullPrompt, effectiveOptions)
        } catch (e: Exception) {
            logger.error("Generation failed: $e")
            analyticsService.trackGenerationFailed(generationId, e)
            managedLifecycle.trackOperationError(e, "generate")
            throw CapabilityError.OperationFailed("Generation", e)
        }

        val endTime = currentTimeMillis()
        val totalTimeMs = (endTime - startTime).toDouble()

        // Simple token estimation (~4 chars per token)
        val outputTokens = maxOf(1, generatedText.length / 4)
        val tokensPerSecond = if (totalTimeMs > 0) (outputTokens.toDouble() * 1000.0) / totalTimeMs else 0.0

        // Complete generation tracking
        analyticsService.completeGeneration(
            generationId = generationId,
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            modelId = modelId,
        )

        logger.info("Generation completed: $outputTokens tokens in ${totalTimeMs.toLong()}ms")

        // Extract thinking content if enabled
        val (responseText, thinkingContent, thinkingTokens) = if (options.enableThinking) {
            val extraction = ThinkingTagPattern.autoExtract(generatedText)
            Triple(extraction.responseContent, extraction.thinkingContent, extraction.thinkingTokens)
        } else {
            Triple(generatedText, null, null)
        }

        return LLMGenerationResult(
            text = responseText,
            tokensUsed = outputTokens,
            latencyMs = totalTimeMs,
            performanceMetrics = LLMPerformanceMetrics(
                tokensPerSecond = tokensPerSecond,
                timeToFirstTokenMs = null, // Non-streaming: no TTFT
                inferenceTimeMs = totalTimeMs,
            ),
            thinkingTokensUsed = thinkingTokens,
            thinkingContent = thinkingContent,
        )
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
        val service = managedLifecycle.requireService()
        val modelId = managedLifecycle.resourceIdOrUnknown()
        val effectiveOptions = mergeOptions(options)
        val framework = config?.framework ?: InferenceFramework.LLAMA_CPP
        val enableThinking = options.enableThinking

        logger.info("Starting streaming generation with model: $modelId")

        // Build prompt with system prompt
        val fullPrompt = buildPrompt(
            messages = listOf(Message(role = MessageRole.USER, content = prompt)),
            systemPrompt = effectiveOptions.systemPrompt ?: config?.effectiveSystemPrompt,
        )

        val inputTokens = maxOf(1, fullPrompt.length / 4)

        // Start streaming generation tracking
        val generationId = analyticsService.startStreamingGeneration(modelId, framework)

        // Create the token stream
        val tokenFlow = flow {
            val tokens = mutableListOf<String>()
            var firstTokenTracked = false

            try {
                service.streamGenerate(fullPrompt, effectiveOptions) { token ->
                    // Track first token
                    if (!firstTokenTracked) {
                        analyticsService.trackFirstToken(generationId)
                        firstTokenTracked = true
                    }
                    tokens.add(token)
                }

                // Emit collected tokens
                for ((index, token) in tokens.withIndex()) {
                    emit(token)
                    // Track streaming update periodically (every 10 tokens)
                    if ((index + 1) % 10 == 0) {
                        analyticsService.trackStreamingUpdate(generationId, index + 1)
                    }
                }

                // Complete analytics tracking
                val outputTokens = tokens.size
                analyticsService.completeGeneration(
                    generationId = generationId,
                    inputTokens = inputTokens,
                    outputTokens = outputTokens,
                    modelId = modelId,
                )
            } catch (e: Exception) {
                analyticsService.trackGenerationFailed(generationId, e)
                throw e
            }
        }

        // Create result with metrics accessor
        return LLMStreamingResult(
            stream = tokenFlow,
            getMetrics = {
                // Generate result after streaming completes
                // In a full implementation, metrics would be accumulated during streaming
                val result = generate(prompt, options.copy(streamingEnabled = false))
                result
            },
        )
    }

    // ============================================================================
    // MARK: - Analytics
    // ============================================================================

    /**
     * Get current generation analytics metrics
     */
    fun getAnalyticsMetrics(): GenerationMetrics = analyticsService.getMetrics()

    // ============================================================================
    // MARK: - Private Methods
    // ============================================================================

    private fun mergeOptions(options: LLMGenerationOptions): LLMGenerationOptions {
        val cfg = config ?: return options

        return LLMGenerationOptions(
            maxTokens = if (options.maxTokens > 0) options.maxTokens else cfg.maxTokens,
            temperature = options.temperature,
            topP = options.topP,
            topK = options.topK,
            stopSequences = options.stopSequences,
            streamingEnabled = options.streamingEnabled,
            enableThinking = options.enableThinking,
            maxThinkingTokens = options.maxThinkingTokens,
            systemPrompt = options.systemPrompt ?: cfg.effectiveSystemPrompt,
        )
    }

    /**
     * Build prompt from messages - matches iOS buildPrompt() exactly
     *
     * For LLM services, we should NOT add role markers as they handle their own templating.
     * Just concatenate the messages with newlines. Don't add trailing "Assistant: " - LLM service handles this.
     */
    private fun buildPrompt(
        messages: List<Message>,
        systemPrompt: String?,
    ): String {
        var prompt = ""

        // Add system prompt first if available
        systemPrompt?.let { system ->
            prompt += "$system\n\n"
        }

        // Add messages without role markers - let LLM service handle formatting
        for (message in messages) {
            prompt += "${message.content}\n"
        }

        // Don't add trailing "Assistant: " - LLM service handles this
        return prompt.trim()
    }
}

// ============================================================================
// MARK: - Result Types
// ============================================================================

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

// ============================================================================
// MARK: - ManagedLifecycle Factory
// ============================================================================

/**
 * Factory method to create ManagedLifecycle for LLM
 */
internal fun createLLMManagedLifecycle(): ManagedLifecycle<LLMService> {
    return ManagedLifecycle(
        lifecycle = createLLMLifecycleManager(),
        resourceType = CapabilityResourceType.LLM_MODEL,
        loggerCategory = "LLM.Lifecycle",
    )
}

/**
 * Private helper to create ModelLifecycleManager for LLM
 */
private fun createLLMLifecycleManager(): ModelLifecycleManager<LLMService> {
    val logger = SDKLogger("LLM.Loader")

    return ModelLifecycleManager(
        category = "LLM.Lifecycle",
        loadResource = { resourceId, config ->
            logger.info("Loading LLM model: $resourceId")

            // Get model info - first try ModelInfoService, then ModelRegistry
            var modelInfo = ServiceContainer.shared.modelInfoService.getModel(resourceId)
            if (modelInfo == null) {
                logger.debug("Model not in ModelInfoService, checking ModelRegistry: $resourceId")
                modelInfo = ServiceContainer.shared.modelRegistry.getModel(resourceId)
            }

            if (modelInfo == null) {
                throw SDKError.ModelNotFound("Model not found: $resourceId")
            }

            // Ensure model is downloaded
            val modelPath = modelInfo.localPath
                ?: throw SDKError.ModelNotDownloaded(
                    "Model not downloaded: $resourceId. Please download the model first."
                )

            // Get provider from registry
            val provider = ModuleRegistry.llmProvider(resourceId)
                ?: throw SDKError.ComponentNotInitialized(
                    "No LLM service provider registered for model: $resourceId"
                )

            // Create configuration
            val llmConfig = (config as? LLMConfiguration)
                ?: LLMConfiguration(modelId = resourceId)

            // Create and initialize service
            val service = provider.createLLMService(llmConfig)
            service.initialize(modelPath)

            logger.info("LLM model loaded successfully: $resourceId")
            service
        },
        unloadResource = { service ->
            service.cleanup()
        },
    )
}
