package com.runanywhere.sdk.components.llm

import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * JVM-specific LLM service implementation
 * Enhanced implementation matching iOS patterns with proper JNI integration support
 */
actual class LlamaCppService actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {

    private val _isReady = AtomicBoolean(false)
    private val _currentModel = AtomicReference<String?>(null)
    private val _isGenerating = AtomicBoolean(false)

    actual override val isReady: Boolean
        get() = _isReady.get()

    actual override val currentModel: String?
        get() = _currentModel.get()

    actual override suspend fun initialize(modelPath: String?) {
        if (modelPath == null) {
            throw LLMServiceError.InitializationFailed("Model path is required")
        }

        try {
            // TODO: Implement actual model loading via JNI to llama.cpp
            // For now, simulate model loading with validation

            // Validate model file exists (basic check)
            val file = java.io.File(modelPath)
            if (!file.exists()) {
                throw LLMServiceError.ModelNotFound("Model file not found at: $modelPath")
            }

            // Simulate model loading delay
            kotlinx.coroutines.delay(100)

            // Set model loaded
            _currentModel.set(modelPath)
            _isReady.set(true)
        } catch (e: Exception) {
            throw LLMServiceError.InitializationFailed("Failed to initialize model: ${e.message}")
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String {
        if (!isReady) {
            throw LLMServiceError.NotInitialized
        }

        if (_isGenerating.get()) {
            throw LLMServiceError.ServiceUnavailable("Generation already in progress")
        }

        _isGenerating.set(true)
        try {
            // TODO: Implement actual generation via JNI to llama.cpp
            // For now, provide better mock generation that respects options

            // Simulate processing time based on prompt length and max tokens
            val processingTime = (prompt.length + options.maxTokens) / 10
            kotlinx.coroutines.delay(processingTime.toLong())

            // Generate response that considers configuration
            val responseLength = minOf(options.maxTokens, 150)
            val response = buildString {
                append("LLM Response (model: ${currentModel?.split("/")?.lastOrNull() ?: "unknown"}): ")

                // Add context-aware response based on prompt
                when {
                    prompt.contains("hello", ignoreCase = true) -> append("Hello! How can I help you today?")
                    prompt.contains("explain", ignoreCase = true) -> append("I'll explain this topic for you...")
                    prompt.contains("code", ignoreCase = true) -> append("Here's the code you requested...")
                    else -> append("I understand your request about: ${prompt.take(50)}...")
                }

                // Pad to approximate the requested length
                while (length < responseLength - 20) {
                    append(" This is generated content.")
                }
            }

            return response
        } finally {
            _isGenerating.set(false)
        }
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) {
        if (!isReady) {
            throw LLMServiceError.NotInitialized
        }

        if (_isGenerating.get()) {
            throw LLMServiceError.ServiceUnavailable("Generation already in progress")
        }

        _isGenerating.set(true)
        try {
            // TODO: Implement actual streaming via JNI to llama.cpp
            // For now, provide realistic streaming mock that matches the generation pattern

            val baseResponse = "LLM Streaming Response: "
            val contextualPart = when {
                prompt.contains("hello", ignoreCase = true) -> "Hello! How can I help you today?"
                prompt.contains("explain", ignoreCase = true) -> "I'll explain this topic for you..."
                prompt.contains("code", ignoreCase = true) -> "Here's the code you requested..."
                else -> "I understand your request about: ${prompt.take(30)}..."
            }

            val fullResponse = baseResponse + contextualPart
            val tokens = fullResponse.split(" ")

            // Stream tokens with realistic timing
            for ((index, token) in tokens.withIndex()) {
                onToken(if (index < tokens.size - 1) "$token " else token)
                // Simulate variable streaming speed
                val delay = when {
                    index < 3 -> 150L // Slower initial tokens
                    index < tokens.size - 2 -> 50L // Faster middle tokens
                    else -> 100L // Slower final tokens
                }
                kotlinx.coroutines.delay(delay)
            }
        } finally {
            _isGenerating.set(false)
        }
    }

    actual override suspend fun cleanup() {
        _isReady.set(false)
        _currentModel.set(null)
    }

    actual override suspend fun process(input: LLMInput): LLMOutput {
        val startTime = currentTimeMillis()

        // Build formatted prompt from messages
        val prompt = input.messages.joinToString("\n") { "${it.role}: ${it.content}" }
        val options = input.options ?: RunAnywhereGenerationOptions.DEFAULT

        val text = generate(prompt, options)

        val generationTime = currentTimeMillis() - startTime

        // Calculate realistic token counts
        val promptTokens = getTokenCount(prompt)
        val completionTokens = getTokenCount(text)
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

        return LLMOutput(
            text = text,
            tokenUsage = TokenUsage(promptTokens = promptTokens, completionTokens = completionTokens),
            metadata = GenerationMetadata(
                modelId = currentModel?.split("/")?.lastOrNull() ?: "llamacpp-mock",
                temperature = options.temperature,
                generationTime = generationTime,
                tokensPerSecond = tokensPerSecond
            ),
            finishReason = FinishReason.COMPLETED,
            timestamp = currentTimeMillis()
        )
    }

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        val sessionId = "stream_${System.currentTimeMillis()}"
        val startTime = currentTimeMillis()

        // Build response using the same logic as generate method
        val prompt = input.messages.joinToString("\n") { "${it.role}: ${it.content}" }
        val baseResponse = "LLM Streaming Response: "
        val contextualPart = when {
            prompt.contains("hello", ignoreCase = true) -> "Hello! How can I help you today?"
            prompt.contains("explain", ignoreCase = true) -> "I'll explain this topic for you..."
            prompt.contains("code", ignoreCase = true) -> "Here's the code you requested..."
            else -> "I understand your request about: ${prompt.take(30)}..."
        }

        val fullResponse = baseResponse + contextualPart
        val tokens = fullResponse.split(" ")

        tokens.forEachIndexed { index, token ->
            val isLast = index == tokens.size - 1
            emit(LLMGenerationChunk(
                text = if (isLast) token else "$token ",
                isComplete = isLast,
                tokenCount = 1,
                chunkIndex = index,
                sessionId = sessionId,
                timestamp = currentTimeMillis(),
                finishReason = if (isLast) FinishReason.COMPLETED else null
            ))
            // Variable timing like in streamGenerate
            val delay = when {
                index < 3 -> 150L
                index < tokens.size - 2 -> 50L
                else -> 100L
            }
            kotlinx.coroutines.delay(delay)
        }
    }

    actual override suspend fun loadModel(modelInfo: ModelInfo) {
        initialize(modelInfo.localPath)
    }

    actual override fun cancelCurrent() {
        // In real implementation would cancel current generation
        _isGenerating.set(false)
    }

    actual override fun getTokenCount(text: String): Int {
        // Simplified token counting - roughly 4 characters per token
        return text.length / 4
    }

    actual override fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = getTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= configuration.contextLength
    }
}
