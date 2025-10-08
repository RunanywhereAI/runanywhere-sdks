package com.runanywhere.sdk.components.llm

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.base.ServiceWrapper
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.ComponentInitializationEvent
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * LLM Service Wrapper to allow protocol-based LLM service to work with BaseComponent
 * Exact match with iOS LLMServiceWrapper
 */
class LLMServiceWrapper(
    override var wrappedService: LLMService? = null
) : ServiceWrapper<LLMService>

/**
 * Language Model component following the iOS architecture exactly
 * Matches iOS LLMComponent.swift structure and capabilities
 */
class LLMComponent(
    private val llmConfiguration: LLMConfiguration
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

    // MARK: - Service Creation

    override suspend fun createService(): LLMServiceWrapper {
        // Check if model needs downloading
        llmConfiguration.modelId?.let { modelId ->
            // Resolve actual model path from model registry
            val modelRegistry = serviceContainer?.modelRegistry
            val modelInfo = modelRegistry?.getModel(modelId)

            if (modelInfo != null) {
                modelPath = modelInfo.localPath

                // Check if model needs downloading
                val needsDownload = modelInfo.localPath == null || !modelRegistry.isModelDownloaded(modelId)

                if (needsDownload) {
                    // Emit download required event
                    EventBus.publish(ComponentInitializationEvent.ComponentDownloadRequired(
                        component = componentType.name,
                        modelId = modelId,
                        sizeBytes = modelInfo.downloadSize ?: 1_000_000_000L
                    ))

                    // Download model
                    downloadModel(modelId)

                    // Update model path after download
                    val updatedModelInfo = modelRegistry.getModel(modelId)
                    modelPath = updatedModelInfo?.localPath
                }
            } else {
                // Model not found in registry, use model ID as path
                modelPath = modelId
                logger.warn("Model $modelId not found in registry, using as direct path")
            }
        }

        // Try to get a registered LLM provider from central registry
        val provider = ModuleRegistry.llmProvider(llmConfiguration.modelId)

        if (provider == null) {
            throw SDKError.ComponentNotInitialized(
                "No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.registerLLM(provider)."
            )
        }

        // Check if we have the new LLMServiceProvider interface
        val enhancedProvider = provider as? LLMServiceProvider

        val llmService = if (enhancedProvider != null) {
            // Use the real LLMServiceProvider interface
            enhancedProvider.createLLMService(llmConfiguration)
        } else {
            // Fallback to old interface - create adapter
            object : LLMService {
                override suspend fun initialize(modelPath: String?) {
                    // Initialization handled by provider
                }
                override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String {
                    val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
                        maxTokens = options.maxTokens,
                        temperature = options.temperature,
                        topK = 40,
                        topP = 0.9f,
                        stopSequences = emptyList()
                    )
                    // This fallback shouldn't call provider.generate - not implemented yet
                    throw SDKError.ComponentNotReady("Legacy provider interface not supported, please use LLMServiceProvider")
                }
                override suspend fun streamGenerate(prompt: String, options: RunAnywhereGenerationOptions, onToken: (String) -> Unit) {
                    val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
                        maxTokens = options.maxTokens,
                        temperature = options.temperature,
                        topK = 40,
                        topP = 0.9f,
                        stopSequences = emptyList()
                    )
                    // This fallback shouldn't call provider.generateStream - not implemented yet
                    throw SDKError.ComponentNotReady("Legacy provider interface not supported, please use LLMServiceProvider")
                }
                override val isReady: Boolean get() = true
                override val currentModel: String? get() = llmConfiguration.modelId
                override suspend fun cleanup() {}
            }
        }

        // Initialize the service
        llmService.initialize(modelPath)
        _isModelLoaded = true

        // Wrap and return the service
        return LLMServiceWrapper(llmService)
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
        EventBus.publish(ComponentInitializationEvent.ComponentDownloadStarted(
            component = componentType.name,
            modelId = modelId
        ))

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
                    val downloadedModel = provider.downloadModel(modelId) { progress ->
                        modelLoadProgress = progress.toDouble()
                        EventBus.publish(ComponentInitializationEvent.ComponentDownloadProgress(
                            component = componentType.name,
                            modelId = modelId,
                            progress = progress.toDouble()
                        ))
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
                        EventBus.publish(ComponentInitializationEvent.ComponentDownloadProgress(
                            component = componentType.name,
                            modelId = modelId,
                            progress = progress
                        ))
                        kotlinx.coroutines.delay(100) // 0.1 second
                    }
                }
            }

            // Emit download completed event
            EventBus.publish(ComponentInitializationEvent.ComponentDownloadCompleted(
                component = componentType.name,
                modelId = modelId
            ))

        } catch (e: Exception) {
            logger.error("Failed to download model $modelId: ${e.message}")
            EventBus.publish(ComponentInitializationEvent.ComponentDownloadFailed(
                component = componentType.name,
                modelId = modelId,
                error = e.message ?: "Unknown error"
            ))
            throw e
        }
    }

    // MARK: - Helper Properties

    private val llmService: LLMService?
        get() = service?.wrappedService

    // MARK: - Public API

    /**
     * Generate text from a simple prompt
     */
    suspend fun generate(prompt: String, systemPrompt: String? = null): LLMOutput {
        ensureReady()

        val input = LLMInput(
            messages = listOf(Message(role = MessageRole.USER, content = prompt)),
            systemPrompt = systemPrompt
        )
        return process(input)
    }

    /**
     * Generate text from prompt (overload for compatibility)
     */
    suspend fun generate(prompt: String): LLMOutput {
        return generate(prompt, systemPrompt = null)
    }

    /**
     * Generate with conversation history
     */
    suspend fun generateWithHistory(messages: List<Message>, systemPrompt: String? = null): LLMOutput {
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
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = llmConfiguration.maxTokens,
            temperature = llmConfiguration.temperature.toFloat(),
            streamingEnabled = llmConfiguration.streamingEnabled
        )

        // Build prompt
        val prompt = buildPrompt(input.messages, input.systemPrompt ?: llmConfiguration.effectiveSystemPrompt)

        // Track generation time
        val startTime = currentTimeMillis()

        // Generate response
        val response = service.generate(prompt, options)

        val generationTime = currentTimeMillis() - startTime

        // Calculate tokens (rough estimate - real implementation would get from service)
        val promptTokens = prompt.length / 4
        val completionTokens = response.length / 4
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

        // Create output
        return LLMOutput(
            text = response,
            tokenUsage = TokenUsage(
                promptTokens = promptTokens,
                completionTokens = completionTokens
            ),
            metadata = GenerationMetadata(
                modelId = service.currentModel ?: "unknown",
                temperature = options.temperature,
                generationTime = generationTime,
                tokensPerSecond = tokensPerSecond
            ),
            finishReason = FinishReason.COMPLETED,
            timestamp = currentTimeMillis()
        )
    }

    /**
     * Stream generation matching iOS AsyncThrowingStream pattern
     */
    fun streamGenerate(
        prompt: String,
        systemPrompt: String? = null
    ): Flow<String> = flow {
        ensureReady()

        val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

        val options = RunAnywhereGenerationOptions(
            maxTokens = llmConfiguration.maxTokens,
            temperature = llmConfiguration.temperature.toFloat(),
            streamingEnabled = true
        )

        val fullPrompt = buildPrompt(
            listOf(Message(role = MessageRole.USER, content = prompt)),
            systemPrompt ?: llmConfiguration.effectiveSystemPrompt
        )

        // Stream generation using callback that emits to Flow
        var completed = false
        val tokens = mutableListOf<String>()

        try {
            service.streamGenerate(fullPrompt, options) { token ->
                tokens.add(token)
            }

            // Emit collected tokens
            for (token in tokens) {
                emit(token)
            }
            completed = true
        } catch (e: Exception) {
            throw e
        }
    }

    /**
     * Stream generation with structured input/output
     */
    fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        ensureReady()

        val service = llmService as? EnhancedLLMService ?: throw SDKError.ComponentNotReady("Enhanced LLM service not available")

        // Validate input
        input.validate()

        // Use the enhanced service's streaming capability
        service.streamProcess(input).collect { chunk ->
            emit(chunk)
        }
    }

    /**
     * Get service for compatibility
     */
    fun getService(): LLMService? {
        return llmService
    }

    /**
     * Load a specific model
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        val service = llmService as? EnhancedLLMService ?: throw SDKError.ComponentNotReady("Enhanced LLM service not available")
        service.loadModel(modelInfo)
    }

    /**
     * Cancel current generation
     */
    fun cancelCurrent() {
        val service = llmService as? EnhancedLLMService
        service?.cancelCurrent()
    }

    /**
     * Get token count for text
     */
    fun getTokenCount(text: String): Int {
        val service = llmService as? EnhancedLLMService
        return service?.getTokenCount(text) ?: (text.length / 4) // Fallback estimation
    }

    /**
     * Check if prompt fits within context window
     */
    fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val service = llmService as? EnhancedLLMService
        return service?.fitsInContext(prompt, maxTokens) ?: run {
            val promptTokens = getTokenCount(prompt)
            val totalTokens = promptTokens + maxTokens
            totalTokens <= llmConfiguration.contextLength
        }
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
    fun getConversationContext(): Context? {
        return conversationContext
    }

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

    private fun buildPrompt(messages: List<Message>, systemPrompt: String?): String {
        var prompt = ""

        systemPrompt?.let { system ->
            prompt += "System: $system\n\n"
        }

        for (message in messages) {
            when (message.role) {
                MessageRole.USER -> prompt += "User: ${message.content}\n"
                MessageRole.ASSISTANT -> prompt += "Assistant: ${message.content}\n"
                MessageRole.SYSTEM -> prompt += "System: ${message.content}\n"
            }
        }

        prompt += "Assistant: "
        return prompt
    }
}
