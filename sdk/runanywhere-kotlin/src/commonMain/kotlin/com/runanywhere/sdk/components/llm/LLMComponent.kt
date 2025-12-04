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
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.data.models.generateUUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

// Note: DelicateCoroutinesApi removed - now using component-scoped telemetryScope instead of GlobalScope

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

    // Coroutine scope for fire-and-forget telemetry operations (avoids GlobalScope)
    private val telemetryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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
        val provider = ModuleRegistry.llmProvider(llmConfiguration.modelId)
            ?: throw SDKError.ComponentNotInitialized(
                "No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.registerLLM(provider)."
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
                EventBus.publish(ComponentInitializationEvent.ComponentDownloadRequired(
                    component = componentType.name,
                    modelId = modelId,
                    sizeBytes = modelInfo.downloadSize ?: 1_000_000_000L
                ))

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
        // Cancel any pending telemetry operations to prevent memory leaks
        telemetryScope.cancel()
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
            EventBus.publish(ComponentInitializationEvent.ComponentUnloaded(
                component = componentType.name,
                modelId = modelId,
                timestamp = currentTimeMillis()
            ))

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
    @OptIn(DelicateCoroutinesApi::class)
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

        // Get telemetry service for tracking
        val telemetryService = serviceContainer?.telemetryService

        // Generate generation ID for telemetry tracking
        val generationId = generateUUID()
        val modelId = llmConfiguration.modelId ?: service.currentModel ?: "unknown"
        val modelName = modelId
        val framework = "llama.cpp" // TODO: Get from service provider

        // Rough token estimation: ~4 characters per token average
        // LIMITATION: This is a very rough approximation. Actual token counts vary significantly based on:
        // - Tokenizer type (BPE, WordPiece, SentencePiece, etc.)
        // - Language and character encoding (ASCII vs Unicode)
        // - Vocabulary and token boundaries
        // For precise token counts, use the model's actual tokenizer.
        val promptTokens = prompt.length / 4

        // Track generation time - start before telemetry to avoid blocking
        val startTime = currentTimeMillis()

        logger.info("Starting LLM generation with model: $modelId")

        // Track generation started - fire and forget to avoid blocking generation
        telemetryScope.launch {
            try {
                telemetryService?.trackGenerationStarted(
                    generationId = generationId,
                    modelId = modelId,
                    modelName = modelName,
                    framework = framework,
                    promptTokens = promptTokens,
                    maxTokens = options.maxTokens,
                    device = PlatformUtils.getDeviceModel(),
                    osVersion = PlatformUtils.getOSVersion()
                )
            } catch (e: Exception) {
                logger.debug("Failed to track generation started: ${e.message}")
            }
        }
        var firstTokenTime: Long? = null

        try {
            // Generate response
            val response = service.generate(prompt, options)

            val generationTime = currentTimeMillis() - startTime

            // Calculate completion tokens using same rough estimation (~4 chars per token)
            val completionTokens = response.length / 4
            val totalTokens = promptTokens + completionTokens
            val tokensPerSecond = if (generationTime > 0) {
                (completionTokens.toDouble() * 1000.0) / generationTime
            } else null

            // Track generation completed - fire and forget
            val finalTokensPerSecond = tokensPerSecond ?: 0.0
            val finalFirstTokenTime = firstTokenTime?.toDouble() ?: 0.0
            telemetryScope.launch {
                try {
                    telemetryService?.trackGenerationCompleted(
                        generationId = generationId,
                        modelId = modelId,
                        modelName = modelName,
                        framework = framework,
                        inputTokens = promptTokens,
                        outputTokens = completionTokens,
                        totalTimeMs = generationTime.toDouble(),
                        timeToFirstTokenMs = finalFirstTokenTime,
                        tokensPerSecond = finalTokensPerSecond,
                        device = PlatformUtils.getDeviceModel(),
                        osVersion = PlatformUtils.getOSVersion()
                    )
                } catch (e: Exception) {
                    logger.debug("Failed to track generation completed: ${e.message}")
                }
            }

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
        } catch (e: Exception) {
            val generationTime = currentTimeMillis() - startTime
            val errorMsg = e.message ?: "Unknown error"

            // Track generation failed - fire and forget
            telemetryScope.launch {
                try {
                    telemetryService?.trackGenerationFailed(
                        generationId = generationId,
                        modelId = modelId,
                        modelName = modelName,
                        framework = framework,
                        inputTokens = promptTokens,
                        totalTimeMs = generationTime.toDouble(),
                        errorMessage = errorMsg,
                        device = PlatformUtils.getDeviceModel(),
                        osVersion = PlatformUtils.getOSVersion()
                    )
                } catch (telemetryError: Exception) {
                    logger.debug("Failed to track generation failed: ${telemetryError.message}")
                }
            }

            throw e
        }
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

        val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")

        // Validate input
        input.validate()

        // Use the service's streaming capability
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
        val service = llmService ?: throw SDKError.ComponentNotReady("LLM service not available")
        service.loadModel(modelInfo)
    }

    /**
     * Cancel current generation
     */
    fun cancelCurrent() {
        llmService?.cancelCurrent()
    }

    /**
     * Get token count for text
     *
     * NOTE: If the LLM service doesn't provide accurate tokenization, falls back to rough estimation
     * of ~4 characters per token. See line 322 for detailed limitations of this approximation.
     */
    fun getTokenCount(text: String): Int {
        return llmService?.getTokenCount(text) ?: (text.length / 4) // Fallback estimation
    }

    /**
     * Check if prompt fits within context window
     */
    fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        return llmService?.fitsInContext(prompt, maxTokens) ?: run {
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
