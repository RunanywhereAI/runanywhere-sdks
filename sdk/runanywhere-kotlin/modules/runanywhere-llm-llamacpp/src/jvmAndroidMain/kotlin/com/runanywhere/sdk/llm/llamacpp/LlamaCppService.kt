package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.generation.GenerationOptions
import com.runanywhere.sdk.generation.GenerationResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlin.math.min

/**
 * Actual implementation of LlamaCpp service for JVM and Android platforms
 */
actual class LlamaCppService {
    private val logger = SDKLogger("LlamaCppService")
    private var contextHandle: Long = 0L
    private var modelPath: String? = null
    private var isInitialized = false
    private var modelInfo: ModelInfo? = null

    actual suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        if (!LlamaCppNative.isLoaded()) {
            throw IllegalStateException("llama.cpp native library not loaded")
        }

        if (isInitialized && contextHandle != 0L) {
            cleanup()
        }

        val params = LlamaParams(
            nGpuLayers = determineGpuLayers(),
            nCtx = 2048,
            nBatch = 512,
            nThreads = determineOptimalThreads(),
            useMmap = true,
            useMlock = false,
            f16Kv = true
        )

        contextHandle = LlamaCppNative.llamaInit(modelPath, params)
        if (contextHandle == 0L) {
            throw IllegalStateException("Failed to initialize llama.cpp with model: $modelPath")
        }

        this@LlamaCppService.modelPath = modelPath
        isInitialized = true
        modelInfo = LlamaCppNative.llamaGetModelInfo(contextHandle)

        logger.info("Initialized llama.cpp with model: ${modelInfo?.name}")
        logger.debug("Model info: $modelInfo")
    }

    actual suspend fun generate(
        prompt: String,
        options: GenerationOptions
    ): GenerationResult = withContext(Dispatchers.Default) {
        if (!isInitialized || contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val startTime = System.currentTimeMillis()

        val params = GenerationParams(
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            topK = options.topK,
            topP = options.topP,
            repeatPenalty = 1.1f,
            stopSequences = options.stopSequences
        )

        val nativeResult = LlamaCppNative.llamaGenerate(contextHandle, prompt, params)

        val totalTime = System.currentTimeMillis() - startTime

        GenerationResult(
            text = nativeResult.text,
            tokensUsed = nativeResult.tokensGenerated + nativeResult.tokensEvaluated,
            latencyMs = totalTime,
            sessionId = "llama_${System.currentTimeMillis()}",
            model = modelInfo?.name,
            savedAmount = calculateCostSavings(nativeResult.tokensGenerated)
        )
    }

    actual fun generateStream(
        prompt: String,
        options: GenerationOptions
    ): Flow<String> = flow {
        if (!isInitialized || contextHandle == 0L) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val params = GenerationParams(
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            topK = options.topK,
            topP = options.topP,
            repeatPenalty = 1.1f,
            stopSequences = options.stopSequences
        )

        // Create a channel for streaming tokens
        val tokens = mutableListOf<String>()

        withContext(Dispatchers.Default) {
            LlamaCppNative.llamaGenerateStream(contextHandle, prompt, params) { token ->
                tokens.add(token)
            }
        }

        // Emit collected tokens
        for (token in tokens) {
            emit(token)
        }
    }

    actual suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (contextHandle != 0L) {
            LlamaCppNative.llamaFree(contextHandle)
            contextHandle = 0L
            isInitialized = false
            modelInfo = null
            logger.info("Cleaned up llama.cpp context")
        }
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

    private fun calculateCostSavings(tokensGenerated: Int): Double {
        // Rough estimate: $0.001 per 1000 tokens for cloud APIs
        val cloudCostPer1000 = 0.001
        return (tokensGenerated / 1000.0) * cloudCostPer1000
    }

    // Additional utility methods

    fun isReady(): Boolean = isInitialized && contextHandle != 0L

    fun getModelInfo(): ModelInfo? = modelInfo

    suspend fun getMemoryUsage(): MemoryUsage? = withContext(Dispatchers.IO) {
        if (contextHandle != 0L) {
            LlamaCppNative.llamaGetMemoryUsage(contextHandle)
        } else null
    }

    suspend fun tokenize(text: String): IntArray = withContext(Dispatchers.Default) {
        if (!isInitialized) throw IllegalStateException("Service not initialized")
        LlamaCppNative.llamaTokenize(contextHandle, text)
    }

    suspend fun getTokenCount(text: String): Int = withContext(Dispatchers.Default) {
        if (!isInitialized) throw IllegalStateException("Service not initialized")
        LlamaCppNative.llamaGetTokenCount(contextHandle, text)
    }
}
