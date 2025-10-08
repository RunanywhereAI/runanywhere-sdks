package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMInput
import com.runanywhere.sdk.components.llm.LLMOutput
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlin.math.min

/**
 * Actual implementation of LlamaCpp service for JVM and Android platforms
 */
actual class LlamaCppService actual constructor(private val configuration: LLMConfiguration) : EnhancedLLMService {
    private val logger = SDKLogger("LlamaCppService")
    private var contextHandle: Long = 0L
    private var modelPath: String? = null
    private var isInitialized = false
    private var modelInfo: com.runanywhere.sdk.models.ModelInfo? = null

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (!LlamaCppNative.isLoaded()) {
            logger.warn("llama.cpp native library not loaded, using mock mode")
            // Mock initialization for development/testing
            this@LlamaCppService.modelPath = actualModelPath
            isInitialized = true
            modelInfo = createMockModelInfo()
            logger.info("Initialized llama.cpp in mock mode with model: ${modelInfo?.name}")
            return@withContext
        }

        if (isInitialized && contextHandle != 0L) {
            cleanup()
        }

        val params = LlamaParams(
            nGpuLayers = configuration.gpuLayers ?: determineGpuLayers(),
            nCtx = configuration.contextLength,
            nBatch = 512,
            nThreads = configuration.cpuThreads ?: determineOptimalThreads(),
            useMmap = configuration.memoryMapping,
            useMlock = configuration.memoryLock,
            f16Kv = true
        )

        contextHandle = LlamaCppNative.llamaInit(actualModelPath, params)
        if (contextHandle == 0L) {
            throw IllegalStateException("Failed to initialize llama.cpp with model: $actualModelPath")
        }

        this@LlamaCppService.modelPath = actualModelPath
        isInitialized = true
        modelInfo = convertToSDKModelInfo(LlamaCppNative.llamaGetModelInfo(contextHandle), actualModelPath)

        logger.info("Initialized llama.cpp with model: ${modelInfo?.name}")
        logger.debug("Model info: $modelInfo")
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.Default) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        // Mock mode when native library not available
        if (!LlamaCppNative.isLoaded()) {
            return@withContext generateMockResponse(prompt)
        }

        if (contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized properly")
        }

        val params = GenerationParams(
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            topK = 40, // Default value
            topP = 0.95f, // Default value
            repeatPenalty = 1.1f,
            stopSequences = options.stopSequences
        )

        val nativeResult = LlamaCppNative.llamaGenerate(contextHandle, prompt, params)
        return@withContext nativeResult.text
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.Default) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        // Mock mode when native library not available
        if (!LlamaCppNative.isLoaded()) {
            streamMockResponse(prompt, onToken)
            return@withContext
        }

        if (contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized properly")
        }

        val params = GenerationParams(
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            topK = 40, // Default value
            topP = 0.95f, // Default value
            repeatPenalty = 1.1f,
            stopSequences = options.stopSequences
        )

        LlamaCppNative.llamaGenerateStream(contextHandle, prompt, params) { token ->
            onToken(token)
        }
    }

    actual override suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (LlamaCppNative.isLoaded() && contextHandle != 0L) {
            LlamaCppNative.llamaFree(contextHandle)
            contextHandle = 0L
        }
        isInitialized = false
        modelInfo = null
        logger.info("Cleaned up llama.cpp context")
    }

    // Interface properties
    actual override val isReady: Boolean
        get() = isInitialized && (contextHandle != 0L || !LlamaCppNative.isLoaded())

    actual override val currentModel: String?
        get() = modelInfo?.name ?: modelPath?.split("/")?.lastOrNull()

    // EnhancedLLMService implementation
    actual override suspend fun process(input: LLMInput): LLMOutput {
        if (!isInitialized || contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val startTime = com.runanywhere.sdk.foundation.currentTimeMillis()

        // Build prompt from messages
        val prompt = buildPrompt(input.messages, input.systemPrompt)

        // Use provided options or defaults
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = false
        )

        // Generate text
        val response = generate(prompt, options)

        val generationTime = com.runanywhere.sdk.foundation.currentTimeMillis() - startTime

        // Calculate token usage (rough estimate)
        val promptTokens = getTokenCount(prompt)
        val completionTokens = getTokenCount(response)
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

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
        if (!isInitialized || contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val prompt = buildPrompt(input.messages, input.systemPrompt)
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = true
        )

        var chunkCount = 0
        streamGenerate(prompt, options) { token ->
            chunkCount++
            // Emit as LLMGenerationChunk
            val chunk = LLMGenerationChunk(
                text = token,
                isComplete = false,
                chunkIndex = chunkCount,
                timestamp = com.runanywhere.sdk.foundation.currentTimeMillis()
            )
            // Note: This is a simplified approach. Real implementation would need coroutine channels
            // for proper async emission within the callback
        }

        // Emit completion chunk
        emit(LLMGenerationChunk(
            text = "",
            isComplete = true,
            chunkIndex = chunkCount,
            timestamp = com.runanywhere.sdk.foundation.currentTimeMillis()
        ))
    }

    actual override suspend fun loadModel(modelInfo: com.runanywhere.sdk.models.ModelInfo) {
        val localPath = modelInfo.localPath ?: throw IllegalArgumentException("Model has no local path")
        initialize(localPath)
    }

    actual override fun cancelCurrent() {
        // llama.cpp doesn't support cancellation directly
        // This would require implementing a cancellation mechanism in the native layer
        logger.info("Cancellation requested but not implemented in llama.cpp")
    }

    actual override fun getTokenCount(text: String): Int {
        return if (isInitialized) {
            try {
                LlamaCppNative.llamaGetTokenCount(contextHandle, text)
            } catch (e: Exception) {
                // Fallback to rough estimation
                text.length / 4
            }
        } else {
            // Fallback to rough estimation
            text.length / 4
        }
    }

    actual override fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = getTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= configuration.contextLength
    }

    // Helper methods

    private fun determineGpuLayers(): Int {
        val gpuInfo = LlamaCppNative.llamaGetGpuInfo()
        return if (gpuInfo != null && gpuInfo.availableMemory > 4_000_000_000L) {
            // If GPU has more than 4GB available, offload layers
            35 // Typical for 7B models
        } else {
            0 // CPU only
        }
    }

    private fun determineOptimalThreads(): Int {
        return min(Runtime.getRuntime().availableProcessors() - 1, 8)
    }

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

    // Additional utility methods for compatibility

    suspend fun getMemoryUsage(): MemoryUsage? = withContext(Dispatchers.IO) {
        if (contextHandle != 0L) {
            LlamaCppNative.llamaGetMemoryUsage(contextHandle)
        } else null
    }

    suspend fun tokenize(text: String): IntArray = withContext(Dispatchers.Default) {
        if (!isInitialized) throw IllegalStateException("Service not initialized")
        LlamaCppNative.llamaTokenize(contextHandle, text)
    }

    // Mock mode helpers for development/testing
    private fun createMockModelInfo(): com.runanywhere.sdk.models.ModelInfo {
        return com.runanywhere.sdk.models.ModelInfo(
            id = modelPath ?: "mock-model",
            name = "Mock LLM Model",
            category = com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE,
            format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF,
            downloadURL = null,
            localPath = modelPath,
            downloadSize = 0,
            memoryRequired = 0,
            compatibleFrameworks = listOf(com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP),
            preferredFramework = com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = null
        )
    }

    private fun generateMockResponse(prompt: String): String {
        return "Mock response for: ${prompt.take(50)}..."
    }

    private suspend fun streamMockResponse(prompt: String, onToken: (String) -> Unit) {
        val response = generateMockResponse(prompt)
        val words = response.split(" ")
        for (word in words) {
            onToken("$word ")
            kotlinx.coroutines.delay(50) // Simulate streaming
        }
    }
}

// Converter helper
private fun convertToSDKModelInfo(
    nativeInfo: com.runanywhere.sdk.llm.llamacpp.ModelInfo,
    modelPath: String
): com.runanywhere.sdk.models.ModelInfo {
    return com.runanywhere.sdk.models.ModelInfo(
        id = modelPath,
        name = nativeInfo.name,
        category = com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE,
        format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF,
        downloadURL = null,
        localPath = modelPath,
        downloadSize = nativeInfo.fileSize,
        memoryRequired = nativeInfo.fileSize,
        compatibleFrameworks = listOf(com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP),
        preferredFramework = com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP,
        contextLength = nativeInfo.contextLength,
        supportsThinking = false,
        metadata = null
    )
}
