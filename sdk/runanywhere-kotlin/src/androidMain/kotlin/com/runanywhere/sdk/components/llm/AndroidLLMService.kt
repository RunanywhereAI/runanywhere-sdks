package com.runanywhere.sdk.components.llm

import com.runanywhere.sdk.models.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Android-specific LLM service implementation
 * Simplified implementation matching iOS without unnecessary adapters
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

        // Mock initialization for now - in real implementation would initialize Android-specific libraries
        _currentModel.set(modelPath)
        _isReady.set(true)
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
            // Mock generation - in real implementation would call Android native library
            return "Android generated response for: $prompt"
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
            // Mock streaming generation
            val tokens = listOf("Android ", "generated ", "response ", "for: ", prompt)
            tokens.forEach { token ->
                onToken(token)
                kotlinx.coroutines.delay(100)
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
        val text = generate(
            input.messages.joinToString("\n") { "${it.role}: ${it.content}" },
            input.options ?: RunAnywhereGenerationOptions.DEFAULT
        )

        return LLMOutput(
            text = text,
            tokenUsage = TokenUsage(promptTokens = 10, completionTokens = 20),
            metadata = GenerationMetadata(
                modelId = currentModel ?: "unknown",
                temperature = configuration.temperature.toFloat(),
                generationTime = 1000L
            ),
            finishReason = FinishReason.COMPLETED
        )
    }

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        val messages = input.messages.joinToString("\n") { "${it.role}: ${it.content}" }
        val tokens = listOf("Android ", "generated ", "response ", "for: ", messages)

        tokens.forEachIndexed { index, token ->
            emit(LLMGenerationChunk(
                text = token,
                isComplete = index == tokens.size - 1,
                tokenCount = 1,
                chunkIndex = index
            ))
            kotlinx.coroutines.delay(100)
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
