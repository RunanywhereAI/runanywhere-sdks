package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/**
 * LlamaCpp service implementation using the new LLamaAndroid wrapper
 * This wraps the low-level streaming API into our SDK interfaces
 */
actual class LlamaCppService actual constructor(private val configuration: LLMConfiguration) : EnhancedLLMService {
    private val logger = SDKLogger("LlamaCppService")
    private val llama = LLamaAndroid.instance()
    private var modelPath: String? = null
    private var isInitialized = false

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

        val result = StringBuilder()
        var tokenCount = 0
        val maxTokens = options.maxTokens

        // Use formatChat = false since we're manually formatting with Qwen template
        llama.send(prompt, formatChat = false).collect { token ->
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

        logger.info("🚀 streamGenerate called with prompt length: ${prompt.length}")
        logger.info("📝 First 200 chars of prompt: ${prompt.take(200)}")
        logger.info("⚙️ Options: maxTokens=${options.maxTokens}, temp=${options.temperature}, streaming=${options.streamingEnabled}")

        var tokenCount = 0
        val maxTokens = options.maxTokens

        // Use formatChat = false since we're manually formatting with Qwen template
        llama.send(prompt, formatChat = false).collect { token ->
            logger.info("🔤 Token #$tokenCount: '$token'")
            onToken(token)
            tokenCount++
            if (tokenCount >= maxTokens) {
                logger.info("⛔ Reached maxTokens limit: $maxTokens")
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

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> {
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

        logger.info("🚀 Starting llama.send() with formatChat=false, maxTokens=$maxTokens")

        // Use formatChat = false since we're manually formatting with Qwen template
        return llama.send(prompt, formatChat = false).map { token ->
            val currentChunk = chunkIndex++
            val currentTokens = tokenCount++
            val isComplete = currentTokens >= maxTokens

            logger.info("🔤 Stream token #$currentTokens: '$token' (len=${token.length})")

            LLMGenerationChunk(
                text = token,
                isComplete = isComplete,
                chunkIndex = currentChunk,
                timestamp = com.runanywhere.sdk.foundation.currentTimeMillis()
            )
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

    private fun buildPrompt(messages: List<Message>, systemPrompt: String?): String {
        val prompt = StringBuilder()

        // Use Qwen2 chat template format
        // Format: <|im_start|>role\ncontent<|im_end|>\n

        // Add system prompt (always include for Qwen2)
        // Use a more helpful default that instructs the model to be concise and relevant
        val system = systemPrompt ?: """You are a helpful, friendly AI assistant.
Answer questions clearly and concisely.
Be direct and relevant to the user's query.
Keep responses focused and helpful."""

        prompt.append("<|im_start|>system\n")
        prompt.append(system)
        prompt.append("<|im_end|>\n")

        // Add all messages from conversation history
        for (message in messages) {
            val role = when (message.role) {
                MessageRole.USER -> "user"
                MessageRole.ASSISTANT -> "assistant"
                MessageRole.SYSTEM -> "system"
            }
            prompt.append("<|im_start|>$role\n")
            prompt.append(message.content)
            prompt.append("<|im_end|>\n")
        }

        // Start the assistant's response
        prompt.append("<|im_start|>assistant\n")

        return prompt.toString()
    }
}
