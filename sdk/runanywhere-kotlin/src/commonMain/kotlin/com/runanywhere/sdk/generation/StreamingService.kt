package com.runanywhere.sdk.generation

import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.LoadedModelWithService
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Service for handling streaming text generation
 */
class StreamingService {

    private val logger = SDKLogger("StreamingService")

    // Reference to the currently loaded model and service
    private var currentModel: LoadedModelWithService? = null

    /**
     * Set the current loaded model for streaming
     */
    fun setLoadedModel(model: LoadedModelWithService?) {
        currentModel = model
        if (model != null) {
            logger.info("StreamingService: Model set to ${model.model.id}")
        } else {
            logger.info("StreamingService: Model cleared")
        }
    }

    /**
     * Stream text generation with the specified prompt and options
     * Now uses proper chat template formatting via EnhancedLLMService
     */
    fun stream(
        prompt: String,
        options: GenerationOptions
    ): Flow<GenerationChunk> = flow {
        val model = currentModel
            ?: throw IllegalStateException("No model loaded for streaming. Call loadModel() first.")

        logger.info("🚀 Starting streaming with model: ${model.model.id}")
        logger.info("📝 User prompt: $prompt")

        // Convert to RunAnywhereGenerationOptions
        val llmOptions = RunAnywhereGenerationOptions(
            temperature = options.temperature,
            maxTokens = options.maxTokens,
            streamingEnabled = true
        )

        // Get LLM service - all services now support chat templates automatically
        val llmService = model.service as? LLMService
            ?: throw IllegalStateException("Loaded service is not an LLM service")

        logger.info("✅ Streaming with automatic chat template support")

        // Use streamGenerate - it now automatically applies chat templates internally
        // The user just passes a simple prompt, and the SDK handles everything
        val fullText = StringBuilder()
        llmService.streamGenerate(prompt, llmOptions) { token ->
            fullText.append(token)
        }

        emit(GenerationChunk(
            text = fullText.toString(),
            tokenCount = fullText.length / 4,
            isComplete = true
        ))
    }

    /**
     * Stream with token-by-token generation
     */
    fun streamTokens(
        prompt: String,
        options: GenerationOptions
    ): Flow<TokenChunk> = flow {
        logger.debug("Starting token streaming for prompt: ${prompt.take(50)}...")

        // TODO: Implement actual token streaming
        // This is a mock implementation

        val tokens = listOf("This", " is", " a", " token", " stream", ".")

        for ((index, token) in tokens.withIndex()) {
            val chunk = TokenChunk(
                token = token,
                tokenId = index,
                logProb = -0.5f, // Mock log probability
                isComplete = index == tokens.lastIndex
            )
            emit(chunk)

            // Simulate processing delay
            delay(30)
        }
    }

    /**
     * Stream with partial completions (useful for code generation)
     */
    fun streamPartial(
        prompt: String,
        options: GenerationOptions
    ): Flow<PartialCompletion> = flow {
        logger.debug("Starting partial streaming for prompt: ${prompt.take(50)}...")

        // TODO: Implement actual partial streaming
        // This is a mock implementation

        val parts = listOf(
            "def hello",
            "def hello_world",
            "def hello_world():",
            "def hello_world():\n    ",
            "def hello_world():\n    print",
            "def hello_world():\n    print('Hello, World!')"
        )

        for ((index, part) in parts.withIndex()) {
            val completion = PartialCompletion(
                text = part,
                confidence = 0.9f - (index * 0.05f),
                isComplete = index == parts.lastIndex
            )
            emit(completion)

            // Simulate processing delay
            delay(100)
        }
    }

    /**
     * Cancel current streaming operation
     */
    fun cancelCurrent() {
        // Cancel current streaming operation
        logger.info("Streaming operation cancelled")
    }
}

/**
 * Token chunk for token-level streaming
 */
data class TokenChunk(
    val token: String,
    val tokenId: Int,
    val logProb: Float,
    val isComplete: Boolean = false
)

/**
 * Partial completion for incremental generation
 */
data class PartialCompletion(
    val text: String,
    val confidence: Float,
    val isComplete: Boolean = false
)
