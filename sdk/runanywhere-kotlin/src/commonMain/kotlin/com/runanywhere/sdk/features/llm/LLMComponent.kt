package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.BaseComponent
import com.runanywhere.sdk.core.capabilities.SDKComponent
import com.runanywhere.sdk.core.capabilities.ServiceWrapper
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.ComponentInitializationEvent
import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * LLM Service Wrapper to allow protocol-based LLM service to work with BaseComponent
 * Exact match with iOS LLMServiceWrapper
 */
class LLMServiceWrapper(
    override var wrappedService: LLMService? = null,
) : ServiceWrapper<LLMService>

/**
 * Language Model component following the iOS architecture exactly
 * Matches iOS LLMComponent.swift structure and capabilities
 *
 * @param llmConfiguration Configuration for the LLM component
 * @param analyticsService Optional analytics service for tracking generation metrics (defaults to new instance)
 */
class LLMComponent(
    private val llmConfiguration: LLMConfiguration,
    private val analyticsService: GenerationAnalyticsService = GenerationAnalyticsService(),
) : BaseComponent<LLMServiceWrapper>(llmConfiguration) {
    companion object {
        val componentType: SDKComponent = SDKComponent.LLM
    }

    override val componentType: SDKComponent = SDKComponent.LLM

    private val logger = SDKLogger("LLMComponent")
    private val serviceContainer: ServiceContainer? = ServiceContainer.shared

    // MARK: - Properties

    private var conversationContext: Context? = null
    private var _isModelLoaded = false
    private var modelPath: String? = null
    private var modelLoadProgress: Double = 0.0

    // MARK: - Initialization

    init {
        // Preload context if provided
        llmConfiguration.preloadContext?.let { preloadContext ->
            this.conversationContext = Context(systemPrompt = preloadContext)
        }
    }

    // MARK: - Service Creation (iOS-aligned pattern)

    /**
     * Create LLM service - matches Swift SDK pattern
     * Separated from model downloading for clarity
     */
    override suspend fun createService(): LLMServiceWrapper {
        // 1. Ensure model is available locally (download if needed)
        ensureModelAvailable()

        // 2. Get provider from registry (iOS pattern)
        val provider =
            ModuleRegistry.llmProvider(llmConfiguration.modelId)
                ?: throw SDKError.ComponentNotInitialized(
                    "No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.registerLLM(provider).",
                )

        // 3. Create service via provider (iOS pattern)
        val llmService = provider.createLLMService(llmConfiguration)

        // 4. Initialize the service with model path
        llmService.initialize(modelPath)
        _isModelLoaded = true

        // 5. Wrap and return
        return LLMServiceWrapper(llmService)
    }

    /**
     * Ensure model is available locally (download if needed)
     * Separated for clarity - matches iOS ModelLoadingService pattern
     */
    private suspend fun ensureModelAvailable() {
        val modelId = llmConfiguration.modelId ?: return

        // Get model info from registry
        val modelRegistry = serviceContainer?.modelRegistry
        val modelInfo = modelRegistry?.getModel(modelId)

        if (modelInfo != null) {
            modelPath = modelInfo.localPath

            // Check if model needs downloading
            val needsDownload = modelInfo.localPath == null || !modelRegistry.isModelDownloaded(modelId)

            if (needsDownload) {
                // Emit download required event
                EventPublisher.track(
                    ComponentInitializationEvent.ComponentDownloadRequired(
                        component = componentType.name,
                        modelId = modelId,
                        sizeBytes = modelInfo.downloadSize ?: 1_000_000_000L,
                    ),
                )

                // Download model
                logger.info("⬇️  Downloading model: $modelId")
                downloadModel(modelId)

                // Update model path after download
                val updatedModelInfo = modelRegistry.getModel(modelId)
                modelPath = updatedModelInfo?.localPath
                logger.info("✅ Model downloaded: $modelId")
            } else {
                logger.info("✅ Model already available: $modelId")
            }
        } else {
            // Model not found in registry, use model ID as path
            modelPath = modelId
            logger.warn("⚠️  Model $modelId not found in registry, using as direct path")
        }
    }

    override suspend fun performCleanup() {
        service?.wrappedService?.cleanup()
        _isModelLoaded = false
        modelPath = null
        conversationContext = null
    }

    // MARK: - Model Management

    private suspend fun downloadModel(modelId: String) {
        // Emit download started event
        EventPublisher.track(
            ComponentInitializationEvent.ComponentDownloadStarted(
                component = componentType.name,
                modelId = modelId,
            ),
        )

        try {
            // First try to get model info from registry
            val modelInfo = serviceContainer?.modelRegistry?.getModel(modelId)

            if (modelInfo != null && modelInfo.downloadURL != null) {
                // Use model manager to download from URL
                logger.info("Downloading model $modelId from URL: ${modelInfo.downloadURL}")
                val downloadedPath = serviceContainer?.modelManager?.ensureModel(modelInfo)

                // Update model registry with local path
                val updatedModelInfo = modelInfo.copy(localPath = downloadedPath)
                serviceContainer?.modelRegistry?.updateModel(updatedModelInfo)
                logger.info("Model $modelId downloaded successfully to: $downloadedPath")
            } else {
                // Try to get the LLM provider to handle the download (legacy support)
                val provider = ModuleRegistry.llmProvider(modelId)
                if (provider != null) {
                    // Use provider to download the model
                    val downloadedModel =
                        provider.downloadModel(modelId) { progress ->
                            modelLoadProgress = progress.toDouble()
                            EventPublisher.track(
                                ComponentInitializationEvent.ComponentDownloadProgress(
                                    component = componentType.name,
                                    modelId = modelId,
                                    progress = progress.toDouble(),
                                ),
                            )
                        }

                    // Update model registry with downloaded model info
                    serviceContainer?.modelRegistry?.registerModel(downloadedModel)
                    logger.info("Model $modelId downloaded successfully via provider")
                } else {
                    // Fallback: simulate download with progress for development
                    logger.warn("No provider found for model $modelId, simulating download")
                    for (i in 0..10) {
                        val progress = i / 10.0
                        modelLoadProgress = progress
                        EventPublisher.track(
                            ComponentInitializationEvent.ComponentDownloadProgress(
                                component = componentType.name,
                                modelId = modelId,
                                progress = progress,
                            ),
                        )
                        kotlinx.coroutines.delay(100) // 0.1 second
                    }
                }
            }

            // Emit download completed event
            EventPublisher.track(
                ComponentInitializationEvent.ComponentDownloadCompleted(
                    component = componentType.name,
                    modelId = modelId,
                ),
            )
        } catch (e: Exception) {
            logger.error("Failed to download model $modelId: ${e.message}")
            EventPublisher.track(
                ComponentInitializationEvent.ComponentDownloadFailed(
                    component = componentType.name,
                    modelId = modelId,
                    error = e.message ?: "Unknown error",
                ),
            )
            throw e
        }
    }

    /**
     * Unload the currently loaded model from memory.
     * Matches Swift SDK's unloadModel() API.
     *
     * @throws SDKError.ComponentNotReady if no model is loaded
     */
    suspend fun unloadModel() {
        if (!_isModelLoaded || service?.wrappedService == null) {
            logger.warn("No model loaded to unload")
            return
        }

        val modelId = llmConfiguration.modelId ?: "unknown"
        logger.info("Unloading model: $modelId")

        try {
            // Call service cleanup
            service?.wrappedService?.cleanup()

            // Clear service reference
            service = null
            _isModelLoaded = false
            modelPath = null

            // Publish event
            EventPublisher.track(
                ComponentInitializationEvent.ComponentUnloaded(
                    component = componentType.name,
                    modelId = modelId,
                    timestamp = currentTimeMillis(),
                ),
            )

            logger.info("✅ Model unloaded successfully: $modelId")
        } catch (e: Exception) {
            logger.error("Failed to unload model: $modelId", e)
            throw SDKError.ComponentNotReady("Failed to unload model: ${e.message}")
        }
    }

    /**
     * Get the currently loaded model ID
     */
    val loadedModelId: String?
        get() = if (_isModelLoaded) llmConfiguration.modelId else null

    // MARK: - Helper Properties

    private val llmService: LLMService?
        get() = service?.wrappedService

    // MARK: - Public API

    /**
     * Generate text from a simple prompt
     */
    suspend fun generate(
        prompt: String,
        systemPrompt: String? = null,
    ): LLMOutput {
        ensureReady()

        val input =
            LLMInput(
                messages = listOf(Message(role = MessageRole.USER, content = prompt)),
                systemPrompt = systemPrompt,
            )
        return process(input)
    }

    /**
     * Generate text from prompt (overload for compatibility)
     */
    suspend fun generate(prompt: String): LLMOutput = generate(prompt, systemPrompt = null)

    /**
     * Generate with conversation history
     */
    suspend fun generateWithHistory(
        messages: List<Message>,
        systemPrompt: String? = null,
    ): LLMOutput {
        ensureReady()

        val input = LLMInput(messages = messages, systemPrompt = systemPrompt)
        return process(input)
    }

    /**
     * Process LLM input
     */
    suspend fun process(input: LLMInput): LLMOutput {
        ensureReady()

        val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

        // Validate input
        input.validate()

        // Use provided options or create from configuration
        val options =
            input.options ?: LLMGenerationOptions(
                maxTokens = llmConfiguration.maxTokens,
                temperature = llmConfiguration.temperature.toFloat(),
                streamingEnabled = llmConfiguration.streamingEnabled,
            )

        // Build prompt
        val prompt = buildPrompt(input.messages, input.systemPrompt ?: llmConfiguration.effectiveSystemPrompt)

        val modelId = llmConfiguration.modelId ?: service.currentModel ?: "unknown"

        // Determine framework from configuration or default
        val framework = llmConfiguration.framework ?: InferenceFramework.LLAMA_CPP

        // Rough token estimation: ~4 characters per token average
        // LIMITATION: This is a very rough approximation. Actual token counts vary significantly based on:
        // - Tokenizer type (BPE, WordPiece, SentencePiece, etc.)
        // - Language and character encoding (ASCII vs Unicode)
        // - Vocabulary and token boundaries
        // For precise token counts, use the model's actual tokenizer.
        val promptTokens = prompt.length / 4

        // Track generation time
        val startTime = currentTimeMillis()

        logger.info("Starting LLM generation with model: $modelId")

        // Start analytics tracking (non-streaming)
        val generationId = analyticsService.startGeneration(modelId, framework)

        try {
            // Generate response
            val response = service.generate(prompt, options)

            val generationTime = currentTimeMillis() - startTime

            // Calculate completion tokens using same rough estimation (~4 chars per token)
            val completionTokens = response.length / 4
            val tokensPerSecond =
                if (generationTime > 0) {
                    (completionTokens.toDouble() * 1000.0) / generationTime
                } else {
                    null
                }

            // Complete analytics tracking
            analyticsService.completeGeneration(
                generationId = generationId,
                inputTokens = promptTokens,
                outputTokens = completionTokens,
                modelId = modelId,
            )

            // Create output
            return LLMOutput(
                text = response,
                tokenUsage =
                    TokenUsage(
                        promptTokens = promptTokens,
                        completionTokens = completionTokens,
                    ),
                metadata =
                    GenerationMetadata(
                        modelId = service.currentModel ?: "unknown",
                        temperature = options.temperature,
                        generationTime = generationTime,
                        tokensPerSecond = tokensPerSecond,
                    ),
                finishReason = FinishReason.COMPLETED,
                timestamp = currentTimeMillis(),
            )
        } catch (e: Exception) {
            // Track generation failed
            analyticsService.trackGenerationFailed(generationId, e)
            throw e
        }
    }

    /**
     * Stream generation matching iOS AsyncThrowingStream pattern
     */
    fun streamGenerate(
        prompt: String,
        systemPrompt: String? = null,
    ): Flow<String> =
        flow {
            ensureReady()

            val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

            val options =
                LLMGenerationOptions(
                    maxTokens = llmConfiguration.maxTokens,
                    temperature = llmConfiguration.temperature.toFloat(),
                    streamingEnabled = true,
                )

            val fullPrompt =
                buildPrompt(
                    listOf(Message(role = MessageRole.USER, content = prompt)),
                    systemPrompt ?: llmConfiguration.effectiveSystemPrompt,
                )

            val modelId = llmConfiguration.modelId ?: service.currentModel ?: "unknown"
            val framework = llmConfiguration.framework ?: InferenceFramework.LLAMA_CPP
            val promptTokens = fullPrompt.length / 4

            // Start analytics tracking (streaming)
            val generationId = analyticsService.startStreamingGeneration(modelId, framework)

            // Stream generation using callback that emits to Flow
            val tokens = mutableListOf<String>()
            var firstTokenTracked = false

            try {
                service.streamGenerate(fullPrompt, options) { token ->
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
                    // Track streaming update periodically (every 10 tokens to avoid chatty events)
                    if ((index + 1) % 10 == 0) {
                        analyticsService.trackStreamingUpdate(generationId, index + 1)
                    }
                }

                // Complete analytics tracking
                val outputTokens = tokens.size
                analyticsService.completeGeneration(
                    generationId = generationId,
                    inputTokens = promptTokens,
                    outputTokens = outputTokens,
                    modelId = modelId,
                )
            } catch (e: Exception) {
                analyticsService.trackGenerationFailed(generationId, e)
                throw e
            }
        }

    /**
     * Stream generation with structured input/output
     * Component-level method that builds the prompt and delegates to streamGenerate
     */
    fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> =
        flow {
            ensureReady()

            val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

            // Validate input
            input.validate()

            // Use provided options or create from configuration
            val options =
                input.options ?: LLMGenerationOptions(
                    maxTokens = llmConfiguration.maxTokens,
                    temperature = llmConfiguration.temperature.toFloat(),
                    streamingEnabled = true,
                )

            // Build prompt from messages
            val prompt = buildPrompt(input.messages, input.systemPrompt ?: llmConfiguration.effectiveSystemPrompt)

            val modelId = llmConfiguration.modelId ?: service.currentModel ?: "unknown"
            val framework = llmConfiguration.framework ?: InferenceFramework.LLAMA_CPP
            val promptTokens = prompt.length / 4

            // Start analytics tracking (streaming)
            val generationId = analyticsService.startStreamingGeneration(modelId, framework)

            // Track chunks for structured output
            var chunkIndex = 0
            val sessionId = generationId // Use generation ID as session ID for correlation

            // Collect tokens from streaming service
            val tokens = mutableListOf<String>()
            var firstTokenTracked = false

            try {
                service.streamGenerate(prompt, options) { token ->
                    // Track first token
                    if (!firstTokenTracked) {
                        analyticsService.trackFirstToken(generationId)
                        firstTokenTracked = true
                    }
                    tokens.add(token)
                }

                // Emit collected tokens as chunks
                for ((index, token) in tokens.withIndex()) {
                    emit(
                        LLMGenerationChunk(
                            text = token,
                            isComplete = false,
                            tokenCount = 1,
                            timestamp = currentTimeMillis(),
                            chunkIndex = chunkIndex++,
                            sessionId = sessionId,
                            finishReason = null,
                        ),
                    )

                    // Track streaming update periodically (every 10 tokens)
                    if ((index + 1) % 10 == 0) {
                        analyticsService.trackStreamingUpdate(generationId, index + 1)
                    }
                }

                // Complete analytics tracking
                val outputTokens = tokens.size
                analyticsService.completeGeneration(
                    generationId = generationId,
                    inputTokens = promptTokens,
                    outputTokens = outputTokens,
                    modelId = modelId,
                )

                // Emit final chunk
                emit(
                    LLMGenerationChunk(
                        text = "",
                        isComplete = true,
                        tokenCount = 0,
                        timestamp = currentTimeMillis(),
                        chunkIndex = chunkIndex,
                        sessionId = sessionId,
                        finishReason = FinishReason.COMPLETED,
                    ),
                )
            } catch (e: Exception) {
                analyticsService.trackGenerationFailed(generationId, e)
                throw e
            }
        }

    /**
     * Get service for compatibility
     */
    fun getService(): LLMService? = llmService

    /**
     * Load a specific model
     * Note: In iOS architecture, model loading is handled during service creation via configuration.
     * This method re-initializes the service with the new model path.
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

        // Update model path and re-initialize service
        modelPath = modelInfo.localPath ?: modelInfo.id
        service.initialize(modelPath)
        _isModelLoaded = true

        logger.info("Model loaded: ${modelInfo.name}")
    }

    /**
     * Cancel current generation
     * Note: This is a component-level utility not part of iOS LLMService protocol.
     * Individual service implementations may support cancellation through their own mechanisms.
     */
    fun cancelCurrent() {
        // Component-level cancellation tracking could be added here
        // For now, this is a placeholder as iOS doesn't expose this on the service interface
        logger.debug("Cancel requested - individual service implementations may handle differently")
    }

    /**
     * Get token count for text
     *
     * Uses rough estimation of ~4 characters per token.
     * LIMITATION: This is a very rough approximation. Actual token counts vary significantly based on:
     * - Tokenizer type (BPE, WordPiece, SentencePiece, etc.)
     * - Language and character encoding (ASCII vs Unicode)
     * - Vocabulary and token boundaries
     * For precise token counts, use the model's actual tokenizer.
     *
     * Note: This is a component-level utility not part of iOS LLMService protocol.
     */
    fun getTokenCount(text: String): Int {
        return text.length / 4 // Rough estimation: ~4 characters per token
    }

    /**
     * Check if prompt fits within context window
     * Note: This is a component-level utility not part of iOS LLMService protocol.
     */
    fun fitsInContext(
        prompt: String,
        maxTokens: Int,
    ): Boolean {
        val promptTokens = getTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= llmConfiguration.contextLength
    }

    /**
     * Get current model info
     */
    val currentModelInfo: String?
        get() = llmService?.currentModel

    /**
     * Check if model is loaded
     */
    val isModelLoaded: Boolean
        get() = _isModelLoaded && llmService?.isReady == true

    /**
     * Get conversation context
     */
    fun getConversationContext(): Context? = conversationContext

    /**
     * Set conversation context
     */
    fun setConversationContext(context: Context?) {
        conversationContext = context
    }

    /**
     * Clear conversation context
     */
    fun clearConversationContext() {
        conversationContext = null
    }

    // MARK: - Private Helpers

    /**
     * Build prompt from messages - matches iOS buildPrompt() exactly
     *
     * iOS Pattern: For LLM services, we should NOT add role markers as they handle their own templating.
     * Just concatenate the messages with newlines. Don't add trailing "Assistant: " - LLM service handles this.
     *
     * Source: iOS LLMComponent.swift lines 520-536
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
