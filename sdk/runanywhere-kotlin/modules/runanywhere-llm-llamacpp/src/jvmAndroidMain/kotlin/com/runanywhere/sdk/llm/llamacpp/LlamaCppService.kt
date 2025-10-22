package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * LlamaCpp service implementation using the new LLamaAndroid wrapper
 * This wraps the low-level streaming API into our SDK interfaces
 */
actual class LlamaCppService actual constructor(private val configuration: LLMConfiguration) :
    LLMService {
    private val logger = SDKLogger("LlamaCppService")
    private val llama = LLamaAndroid.instance()
    private var modelPath: String? = null
    private var isInitialized = false

    @Volatile
    private var isCleanedUp = false

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (isInitialized) {
            logger.info("Already initialized, unloading previous model")
            cleanup()
        }

        logger.info("Initializing llama.cpp with model: $actualModelPath")

        try {
            // Create config from LLMConfiguration
            val config = LlamaModelConfig(
                contextSize = configuration.contextLength,
                threads = 0, // auto-detect
                temperature = configuration.temperature.toFloat(),
                minP = 0.05f, // Default min-P
                topK = 40 // Default top-K
            )

            llama.load(actualModelPath, config)
            this@LlamaCppService.modelPath = actualModelPath
            isInitialized = true
            logger.info("✅ Initialized llama.cpp successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize llama.cpp", e)
            // Ensure cleanup on initialization failure
            try {
                llama.unload()
            } catch (cleanupException: Exception) {
                logger.error("Error during cleanup after failed initialization", cleanupException)
            }
            isInitialized = false
            this@LlamaCppService.modelPath = null
            throw IllegalStateException("Failed to initialize llama.cpp: ${e.message}", e)
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        // Automatically convert prompt to message and apply chat template
        val userMessage = Message(role = MessageRole.USER, content = prompt)
        val formattedPrompt = buildPrompt(listOf(userMessage), systemPrompt = null)

        val result = StringBuilder()
        var tokenCount = 0
        val maxTokens = options.maxTokens

        // Stream with chat template-formatted prompt
        llama.send(formattedPrompt, parseSpecialTokens = true).collect { token ->
            result.append(token)
            tokenCount++
            if (tokenCount >= maxTokens) {
                return@collect
            }
        }

        result.toString()
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("🚀 streamGenerate called")

        // Automatically convert prompt to message and apply chat template
        // This is transparent to the user - they just pass a string, we handle the rest
        val userMessage = Message(role = MessageRole.USER, content = prompt)
        val formattedPrompt = buildPrompt(listOf(userMessage), systemPrompt = null)

        var tokenCount = 0
        val maxTokens = options.maxTokens

        // Stream with chat template-formatted prompt
        llama.send(formattedPrompt, parseSpecialTokens = true).collect { token ->
            onToken(token)
            tokenCount++
            if (tokenCount >= maxTokens) {
                return@collect
            }
        }
        logger.info("✅ streamGenerate completed with $tokenCount tokens")
    }

    actual override suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (isInitialized) {
            logger.info("Cleaning up llama.cpp context")
            llama.unload()
            isInitialized = false
            modelPath = null
            logger.info("Cleaned up llama.cpp context")
            isCleanedUp = true
        }
    }

    // Interface properties
    actual override val isReady: Boolean
        get() = isInitialized

    actual override val currentModel: String?
        get() = modelPath?.split("/")?.lastOrNull()

    // EnhancedLLMService implementation
    actual override suspend fun process(input: LLMInput): LLMOutput {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("🎯 process() called with ${input.messages.size} messages")
        logger.info("📨 Messages:")
        input.messages.forEach { msg ->
            logger.info("  - ${msg.role}: ${msg.content.take(100)}")
        }
        logger.info("🔧 System prompt: ${input.systemPrompt?.take(100) ?: "null"}")

        val startTime = com.runanywhere.sdk.foundation.currentTimeMillis()

        // Build prompt from messages
        val prompt = buildPrompt(input.messages, input.systemPrompt)
        logger.info("📝 Built prompt length: ${prompt.length} chars")
        logger.info("📝 Full prompt:\n$prompt")
        logger.info("📝 [END OF PROMPT]")

        // Use provided options or defaults
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = false
        )

        // Generate text
        val response = generate(prompt, options)
        logger.info("✅ Generated response: ${response.take(200)}")

        val generationTime = com.runanywhere.sdk.foundation.currentTimeMillis() - startTime

        // Calculate token usage (rough estimate)
        val promptTokens = estimateTokenCount(prompt)
        val completionTokens = estimateTokenCount(response)
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

        logger.info("📊 Stats: ${completionTokens} tokens in ${generationTime}ms (${tokensPerSecond?.toInt() ?: 0} tok/s)")

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

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        logger.info("🌊 streamProcess() called with ${input.messages.size} messages")
        val prompt = buildPrompt(input.messages, input.systemPrompt)
        logger.info("📝 Stream prompt length: ${prompt.length} chars")
        logger.info("📝 Stream prompt (first 300 chars):\n${prompt.take(300)}")

        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = true
        )

        var chunkIndex = 0
        var tokenCount = 0
        val maxTokens = options.maxTokens

        logger.info("🚀 Starting llama.send() with parseSpecialTokens=true, maxTokens=$maxTokens")

        // Always parse special tokens (true) for proper chat template handling
        // This works for Qwen2, LFM2, and other models
        llama.send(prompt, parseSpecialTokens = true).collect { token ->
            val currentChunk = chunkIndex++
            val currentTokens = tokenCount++
            val isComplete = currentTokens >= maxTokens

            logger.info("🔤 Stream token #$currentTokens: '$token' (len=${token.length})")

            emit(LLMGenerationChunk(
                text = token,
                isComplete = isComplete,
                chunkIndex = currentChunk,
                timestamp = com.runanywhere.sdk.foundation.currentTimeMillis()
            ))
        }
    }

    actual override suspend fun loadModel(modelInfo: com.runanywhere.sdk.models.ModelInfo) {
        val localPath = modelInfo.localPath ?: throw IllegalArgumentException("Model has no local path")
        initialize(localPath)
    }

    actual override fun cancelCurrent() {
        // llama.cpp doesn't support cancellation directly in this implementation
        logger.info("Cancellation requested but not implemented in llama.cpp")
    }

    actual override fun getTokenCount(text: String): Int {
        return estimateTokenCount(text)
    }

    actual override fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = estimateTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= configuration.contextLength
    }

    // Helper methods

    private fun estimateTokenCount(text: String): Int {
        // Rough estimation: 1 token ≈ 4 characters
        return text.length / 4
    }

    private suspend fun buildPrompt(messages: List<Message>, systemPrompt: String?): String {
        logger.info("🎯 buildPrompt() called with ${messages.size} messages, systemPrompt=${systemPrompt != null}")

        // Prepare messages list with system prompt if provided
        val allMessages = buildList {
            // Add system prompt as first message if provided
            if (systemPrompt != null) {
                add(Message(
                    role = MessageRole.SYSTEM,
                    content = systemPrompt
                ))
            }

            // Add all conversation messages
            addAll(messages)
        }

        logger.info("📝 Total messages for template: ${allMessages.size}")
        allMessages.forEachIndexed { index, msg ->
            logger.info("  Message $index: ${msg.role} - ${msg.content.take(100)}")
        }

        // Use llama.cpp's built-in chat template
        // This automatically detects and applies the correct template for ANY model:
        // - Qwen2: <|im_start|>role\ncontent<|im_end|>
        // - Llama 3.2: <|begin_of_text|>...<|start_header_id|>role<|end_header_id|>
        // - LFM2: Whatever template is embedded in the model
        // - Any future models: Will work automatically
        logger.info("🔧 Applying llama.cpp chat template (model-specific, automatic)")

        val formattedPrompt = try {
            llama.applyChatTemplate(
                messages = allMessages,
                templateName = null, // Use model's default template
                addAssistantToken = true // Add token to start assistant's response
            )
        } catch (e: Exception) {
            logger.error("❌ Failed to apply chat template, falling back to simple format", e)

            // Fallback to simple format if chat template fails
            // This can happen if the model doesn't have a template defined
            logger.warn("⚠️ Using fallback simple prompt format")
            buildSimpleFallbackPrompt(allMessages)
        }

        logger.info("✅ Final prompt length: ${formattedPrompt.length} chars")
        logger.info("📄 Prompt preview (first 500 chars):\n${formattedPrompt.take(500)}")
        logger.info("📄 Prompt preview (last 200 chars):\n...${formattedPrompt.takeLast(200)}")

        return formattedPrompt
    }

    /**
     * Fallback prompt builder for models without chat templates
     * This is only used if llama_chat_apply_template fails
     */
    private fun buildSimpleFallbackPrompt(messages: List<Message>): String {
        val prompt = StringBuilder()

        for (message in messages) {
            when (message.role) {
                MessageRole.SYSTEM -> {
                    prompt.append("${message.content}\n\n")
                }
                MessageRole.USER -> {
                    prompt.append("User: ${message.content}\n")
                }
                MessageRole.ASSISTANT -> {
                    prompt.append("Assistant: ${message.content}\n")
                }
            }
        }

        // Start assistant response
        prompt.append("Assistant: ")

        return prompt.toString()
    }
}
