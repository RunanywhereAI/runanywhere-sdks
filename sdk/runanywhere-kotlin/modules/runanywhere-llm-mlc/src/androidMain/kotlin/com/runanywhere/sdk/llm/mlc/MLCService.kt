package com.runanywhere.sdk.llm.mlc

import ai.mlc.mlcllm.OpenAIProtocol
import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * MLC-LLM Service implementation for Android
 *
 * Provides on-device LLM inference using MLC-compiled models with GPU acceleration via OpenCL.
 * This is the actual implementation for Android platform.
 *
 * ## Architecture
 * - Uses MLCEngine wrapper for native MLC interaction
 * - Runs on Dispatchers.IO for all blocking operations
 * - Thread-safe via synchronized blocks in MLCEngine
 * - Supports cancellation via volatile flag
 *
 * ## Model Loading
 * MLC models require:
 * 1. Model directory path (modelPath)
 * 2. Model library name (modelLib) - specified in frameworkOptions["modelLib"]
 * 3. Model files: mlc-chat-config.json, params, tokenizer, etc.
 *
 * ## Thread Safety
 * - All public methods use withContext(Dispatchers.IO) for thread safety
 * - MLCEngine is singleton with synchronized methods
 * - shouldCancel flag is volatile for thread-safe cancellation
 */
actual class MLCService actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {

    private val logger = SDKLogger("MLCService")

    // MLC Engine (lazy initialization)
    private var engine: MLCEngine? = null

    // State tracking
    private var modelPath: String? = null
    private var modelLib: String? = null
    private var isInitialized = false
    private var contextLength: Int = configuration.contextLength

    // Cancellation support
    @Volatile
    private var shouldCancel = false

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (isInitialized) {
            logger.info("Already initialized, unloading previous model")
            cleanup()
        }

        logger.info("Initializing MLC-LLM with model: $actualModelPath")

        try {
            // Extract model lib from configuration
            val actualModelLib = configuration.frameworkOptions["modelLib"] as? String
                ?: throw IllegalArgumentException(
                    "Model lib must be specified in configuration.frameworkOptions[\"modelLib\"]. " +
                    "Cannot infer from model path: $actualModelPath"
                )

            // Create engine if needed
            if (engine == null) {
                logger.info("Creating new MLCEngine instance")
                engine = MLCEngine()
            }

            // Load model via MLC Engine
            engine!!.reload(actualModelPath, actualModelLib)

            this@MLCService.modelPath = actualModelPath
            this@MLCService.modelLib = actualModelLib
            isInitialized = true

            logger.info("Initialized MLC-LLM successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize MLC-LLM", e)
            throw IllegalStateException("Failed to initialize MLC-LLM: ${e.message}", e)
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.IO) {
        if (!isInitialized || engine == null) {
            throw IllegalStateException("MLCService not initialized")
        }

        logger.info("Generating text for prompt (length=${prompt.length})")

        shouldCancel = false
        val startTime = getCurrentTimeMillis()
        val generatedText = StringBuilder()

        try {
            // Convert to OpenAI message format
            val messages = listOf(
                OpenAIProtocol.ChatCompletionMessage(
                    role = OpenAIProtocol.ChatCompletionRole.user,
                    content = prompt
                )
            )

            // Create stream options to get usage stats
            val streamOptions = OpenAIProtocol.StreamOptions(include_usage = true)

            // Stream generation and collect all tokens
            val responses = engine!!.chatCompletion(
                messages = messages,
                maxTokens = options.maxTokens,
                temperature = options.temperature?.toFloat(),
                topP = options.topP?.toFloat(),
                stopSequences = options.stop,
                streamOptions = streamOptions
            )

            // Collect all streamed tokens
            for (response in responses) {
                if (shouldCancel) {
                    logger.info("Generation cancelled by user")
                    break
                }

                response.choices.forEach { choice ->
                    choice.delta.content?.let { content ->
                        generatedText.append(content.asText())
                    }
                }
            }

            val endTime = getCurrentTimeMillis()
            val duration = endTime - startTime
            logger.info("Generation completed: ${generatedText.length} chars in ${duration}ms")

            return@withContext generatedText.toString()

        } catch (e: Exception) {
            logger.error("Generation failed", e)
            throw SDKError.ComponentNotReady("Generation failed: ${e.message}")
        }
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (!isInitialized || engine == null) {
            throw IllegalStateException("MLCService not initialized")
        }

        logger.info("Stream generating text for prompt (length=${prompt.length})")

        shouldCancel = false

        try {
            // Convert to OpenAI message format
            val messages = listOf(
                OpenAIProtocol.ChatCompletionMessage(
                    role = OpenAIProtocol.ChatCompletionRole.user,
                    content = prompt
                )
            )

            // Create stream options to get usage stats
            val streamOptions = OpenAIProtocol.StreamOptions(include_usage = true)

            // Stream generation
            val responses = engine!!.chatCompletion(
                messages = messages,
                maxTokens = options.maxTokens,
                temperature = options.temperature?.toFloat(),
                topP = options.topP?.toFloat(),
                stopSequences = options.stop,
                streamOptions = streamOptions
            )

            // Stream tokens to callback
            for (response in responses) {
                if (shouldCancel) {
                    logger.info("Streaming cancelled by user")
                    break
                }

                response.choices.forEach { choice ->
                    choice.delta.content?.let { content ->
                        val token = content.asText()
                        onToken(token)
                    }
                }
            }

            logger.info("Streaming generation completed")

        } catch (e: Exception) {
            logger.error("Streaming generation failed", e)
            throw SDKError.ComponentNotReady("Streaming generation failed: ${e.message}")
        }
    }

    actual override suspend fun process(input: LLMInput): LLMOutput {
        if (!isInitialized || engine == null) {
            throw IllegalStateException("MLCService not initialized")
        }

        logger.info("Processing LLM input (skeleton implementation)")

        // TODO: Implement in Phase 5
        throw SDKError.ComponentNotReady("MLCService process not yet implemented - Phase 5")
    }

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        if (!isInitialized || engine == null) {
            throw IllegalStateException("MLCService not initialized")
        }

        logger.info("Stream processing LLM input (skeleton implementation)")

        // TODO: Implement in Phase 4
        throw SDKError.ComponentNotReady("MLCService streamProcess not yet implemented - Phase 4")
    }

    actual override suspend fun loadModel(modelInfo: ModelInfo) {
        val modelPath = modelInfo.localPath ?: modelInfo.id
        val modelLib = modelInfo.metadata?.additionalProperties?.get("modelLib") as? String
            ?: throw IllegalArgumentException("ModelInfo must contain modelLib in metadata")

        // Store in configuration for reload
        (configuration.frameworkOptions as? MutableMap)?.set("modelLib", modelLib)

        initialize(modelPath)
    }

    actual override fun cancelCurrent() {
        shouldCancel = true
        logger.info("Cancellation requested")
    }

    actual override fun getTokenCount(text: String): Int {
        // Rough estimation: ~4 characters per token
        return text.length / 4
    }

    actual override fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = getTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= contextLength
    }

    actual override suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (isInitialized) {
            logger.info("Cleaning up MLC-LLM context")
            try {
                engine?.unload()
            } catch (e: Exception) {
                logger.error("Error during cleanup", e)
            }
            isInitialized = false
            modelPath = null
            modelLib = null
        }
    }

    actual override val isReady: Boolean
        get() = isInitialized

    actual override val currentModel: String?
        get() = modelPath?.split("/")?.lastOrNull()
}
