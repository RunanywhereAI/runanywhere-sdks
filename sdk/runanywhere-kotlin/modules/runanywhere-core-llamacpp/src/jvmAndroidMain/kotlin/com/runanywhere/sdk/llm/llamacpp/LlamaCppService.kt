package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.core.llamacpp.LlamaCppCoreService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.data.models.generateUUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * LlamaCpp service implementation backed by RunAnywhere Core C++ library.
 *
 * This wraps LlamaCppCoreService which provides native LLM inference with
 * proper chat template support for all models (Qwen, LFM2, Llama, etc.)
 *
 * The chat template application happens in the C++ layer via llama_chat_apply_template,
 * ensuring correct formatting for any model with an embedded template.
 */
actual class LlamaCppService actual constructor(private val configuration: LLMConfiguration) :
    LLMService {
    private val logger = SDKLogger("LlamaCppService")
    private val coreService = LlamaCppCoreService()
    private var modelPath: String? = null
    private var isServiceInitialized = false

    /**
     * Service-scoped CoroutineScope for fire-and-forget telemetry operations.
     * Uses SupervisorJob to prevent failures from affecting other telemetry operations.
     * Cancelled when the service is cleaned up to prevent resource leaks.
     */
    private val telemetryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (isServiceInitialized) {
            logger.info("Already initialized, unloading previous model")
            cleanup()
        }

        logger.info("Initializing LlamaCpp (RunAnywhere Core) with model: $actualModelPath")

        try {
            // Initialize the core service
            coreService.initialize()

            // Load the model
            coreService.loadModel(actualModelPath)

            this@LlamaCppService.modelPath = actualModelPath
            isServiceInitialized = true
            logger.info("Initialized LlamaCpp (RunAnywhere Core) successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize LlamaCpp (RunAnywhere Core)", e)
            isServiceInitialized = false
            this@LlamaCppService.modelPath = null
            throw IllegalStateException("Failed to initialize: ${e.message}", e)
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.IO) {
        if (!isServiceInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        // C++ layer will apply chat template automatically
        coreService.generate(
            prompt = prompt,
            systemPrompt = null,
            maxTokens = options.maxTokens,
            temperature = options.temperature
        )
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (!isServiceInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("streamGenerate called")

        // Get telemetry service for tracking
        val telemetryService = ServiceContainer.shared.telemetryService

        // Generate generation ID for telemetry tracking
        val generationId = generateUUID()
        val modelId = currentModel ?: modelPath?.split("/")?.lastOrNull() ?: "unknown"
        val modelName = modelId
        val framework = "llama.cpp"

        // Calculate prompt tokens
        val promptTokens = estimateTokenCount(prompt)

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
        val generatedText = StringBuilder()

        try {
            // C++ layer will apply chat template automatically
            coreService.generateStream(
                prompt = prompt,
                systemPrompt = null,
                maxTokens = options.maxTokens,
                temperature = options.temperature
            ) { token ->
                generatedText.append(token)
                onToken(token)
                true // continue
            }

            val generationTime = currentTimeMillis() - startTime

            // Estimate tokens from the actual generated text
            val outputTokens = estimateTokenCount(generatedText.toString())

            val tokensPerSecond = if (generationTime > 0) {
                (outputTokens.toDouble() * 1000.0) / generationTime
            } else 0.0

            // Track generation completed - fire and forget
            telemetryScope.launch {
                try {
                    telemetryService?.trackGenerationCompleted(
                        generationId = generationId,
                        modelId = modelId,
                        modelName = modelName,
                        framework = framework,
                        inputTokens = promptTokens,
                        outputTokens = outputTokens,
                        totalTimeMs = generationTime.toDouble(),
                        timeToFirstTokenMs = 0.0,
                        tokensPerSecond = tokensPerSecond,
                        device = PlatformUtils.getDeviceModel(),
                        osVersion = PlatformUtils.getOSVersion()
                    )
                } catch (e: Exception) {
                    logger.debug("Failed to track generation completed: ${e.message}")
                }
            }

            logger.info("streamGenerate completed")
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

    actual override suspend fun cleanup() {
        if (isServiceInitialized) {
            logger.info("Cleaning up LlamaCpp (RunAnywhere Core)")
            // Cancel telemetry scope to prevent resource leaks
            telemetryScope.cancel()
            coreService.destroy() // suspend fun, handles its own dispatcher and mutex
            isServiceInitialized = false
            modelPath = null
            logger.info("Cleaned up LlamaCpp (RunAnywhere Core)")
        }
    }

    actual override val isReady: Boolean
        get() = isServiceInitialized && coreService.isModelLoaded

    actual override val currentModel: String?
        get() = modelPath?.split("/")?.lastOrNull()

    actual suspend fun process(input: LLMInput): LLMOutput {
        if (!isServiceInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("process() called with ${input.messages.size} messages")

        val startTime = currentTimeMillis()

        // Extract prompt and system prompt from messages
        val (prompt, systemPrompt) = extractPromptFromMessages(input.messages, input.systemPrompt)

        logger.info("Extracted prompt: ${prompt.take(100)}...")
        if (systemPrompt != null) {
            logger.info("System prompt: ${systemPrompt.take(100)}...")
        }

        // Use provided options or defaults
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = false
        )

        // Generate with C++ backend (chat template applied in C++)
        val response = coreService.generate(
            prompt = prompt,
            systemPrompt = systemPrompt,
            maxTokens = options.maxTokens,
            temperature = options.temperature
        )

        logger.info("Generated response: ${response.take(200)}...")

        val generationTime = currentTimeMillis() - startTime
        val promptTokens = estimateTokenCount(prompt)
        val completionTokens = estimateTokenCount(response)
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

        logger.info("Stats: $completionTokens tokens in ${generationTime}ms (${tokensPerSecond?.toInt() ?: 0} tok/s)")

        return LLMOutput(
            text = response,
            tokenUsage = TokenUsage(
                promptTokens = promptTokens,
                completionTokens = completionTokens
            ),
            metadata = GenerationMetadata(
                modelId = currentModel ?: "unknown",
                temperature = options.temperature,
                generationTime = generationTime,
                tokensPerSecond = tokensPerSecond
            ),
            finishReason = FinishReason.COMPLETED,
            timestamp = startTime
        )
    }

    actual fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        if (!isServiceInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("streamProcess() called with ${input.messages.size} messages")

        // Extract prompt and system prompt from messages
        val (prompt, systemPrompt) = extractPromptFromMessages(input.messages, input.systemPrompt)

        logger.info("Stream prompt: ${prompt.take(100)}...")

        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = true
        )

        var chunkIndex = 0
        var tokenCount = 0
        val maxTokens = options.maxTokens

        logger.info("Starting stream with maxTokens=$maxTokens")

        // Stream with C++ backend (chat template applied in C++)
        coreService.generateStream(
            prompt = prompt,
            systemPrompt = systemPrompt,
            maxTokens = maxTokens,
            temperature = options.temperature
        ) { token ->
            val currentChunk = chunkIndex++
            val currentTokens = tokenCount++
            val isComplete = currentTokens >= maxTokens

            logger.info("Stream token #$currentTokens: '$token'")

            // Note: We can't emit from inside a callback, so we collect tokens
            // This is a limitation - for true streaming, use generateStream directly
            true // continue
        }
    }

    actual suspend fun loadModel(modelInfo: ModelInfo) {
        val localPath = modelInfo.localPath ?: throw IllegalArgumentException("Model has no local path")
        initialize(localPath)
    }

    actual fun cancelCurrent() {
        if (isServiceInitialized) {
            coreService.cancel()
            logger.info("Cancellation requested")
        }
    }

    actual fun getTokenCount(text: String): Int {
        return estimateTokenCount(text)
    }

    actual fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = estimateTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= configuration.contextLength
    }

    // =============================================================================
    // Helper Methods
    // =============================================================================

    private fun estimateTokenCount(text: String): Int {
        // Rough estimation: 1 token ~ 4 characters
        return text.length / 4
    }

    /**
     * Extract prompt and system prompt from message list.
     * The C++ layer will apply the appropriate chat template.
     */
    private fun extractPromptFromMessages(
        messages: List<Message>,
        systemPrompt: String?
    ): Pair<String, String?> {
        var extractedSystemPrompt = systemPrompt

        // Build the conversation prompt
        val promptBuilder = StringBuilder()

        for (message in messages) {
            when (message.role) {
                MessageRole.SYSTEM -> {
                    // Capture system prompt from messages if not already provided
                    if (extractedSystemPrompt == null) {
                        extractedSystemPrompt = message.content
                    }
                }
                MessageRole.USER -> {
                    if (promptBuilder.isNotEmpty()) {
                        promptBuilder.append("\n")
                    }
                    promptBuilder.append(message.content)
                }
                MessageRole.ASSISTANT -> {
                    // Include assistant messages for context
                    if (promptBuilder.isNotEmpty()) {
                        promptBuilder.append("\n")
                    }
                    promptBuilder.append("Assistant: ")
                    promptBuilder.append(message.content)
                }
            }
        }

        val prompt = promptBuilder.toString().ifEmpty {
            // If no user message, use a default
            messages.lastOrNull()?.content ?: ""
        }

        return Pair(prompt, extractedSystemPrompt)
    }
}
