package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.serialization.Serializable

/**
 * JNI wrapper for llama.cpp library
 * Provides native LLM inference functionality
 */
object LlamaCppNative {
    private val logger = SDKLogger("LlamaCppNative")
    private var isLibraryLoaded = false

    // Native library loading
    init {
        loadNativeLibrary()
    }

    /**
     * Load the native llama.cpp library
     */
    private fun loadNativeLibrary() {
        try {
            System.loadLibrary("llama-jni")
            isLibraryLoaded = true
            logger.info("Successfully loaded llama-jni native library")
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Failed to load llama-jni native library", e)
            isLibraryLoaded = false
        }
    }

    /**
     * Check if native library is loaded
     */
    fun isLoaded(): Boolean = isLibraryLoaded

    // Core initialization and cleanup
    external fun llamaInit(modelPath: String, params: LlamaParams): Long
    external fun llamaFree(contextHandle: Long)

    // Text generation
    external fun llamaGenerate(
        contextHandle: Long,
        prompt: String,
        params: GenerationParams
    ): GenerationNativeResult

    // Streaming generation
    external fun llamaGenerateStream(
        contextHandle: Long,
        prompt: String,
        params: GenerationParams,
        callback: (String) -> Unit
    )

    // Token operations
    external fun llamaTokenize(contextHandle: Long, text: String): IntArray
    external fun llamaDetokenize(contextHandle: Long, tokens: IntArray): String
    external fun llamaGetVocabSize(contextHandle: Long): Int

    // Context management
    external fun llamaGetContextLength(contextHandle: Long): Int
    external fun llamaGetTokenCount(contextHandle: Long, text: String): Int
    external fun llamaResetContext(contextHandle: Long)
    external fun llamaSaveState(contextHandle: Long, path: String): Boolean
    external fun llamaLoadState(contextHandle: Long, path: String): Boolean

    // Model information
    external fun llamaGetModelInfo(contextHandle: Long): ModelInfo
    external fun llamaGetGpuInfo(): GpuInfo?

    // Memory management
    external fun llamaGetMemoryUsage(contextHandle: Long): MemoryUsage
    external fun llamaSetMemoryLimit(maxBytes: Long)
}

/**
 * Llama initialization parameters
 */
@Serializable
data class LlamaParams(
    val nGpuLayers: Int = 0,          // Number of layers to offload to GPU
    val nCtx: Int = 2048,             // Context size
    val nBatch: Int = 512,            // Batch size for prompt processing
    val nThreads: Int = 4,            // Number of threads to use
    val useMmap: Boolean = true,      // Use memory mapping for model
    val useMlock: Boolean = false,    // Lock model in memory
    val f16Kv: Boolean = true,        // Use f16 for KV cache
    val logitsAll: Boolean = false,   // Return logits for all tokens
    val vocabOnly: Boolean = false,   // Only load vocabulary
    val embedding: Boolean = false,   // Enable embedding mode
    val seed: Int = -1                // RNG seed (-1 for random)
)

/**
 * Generation parameters
 */
@Serializable
data class GenerationParams(
    val maxTokens: Int = 512,
    val temperature: Float = 0.8f,
    val topK: Int = 40,
    val topP: Float = 0.95f,
    val repeatPenalty: Float = 1.1f,
    val repeatLastN: Int = 64,
    val penaltyPresent: Float = 0.0f,
    val penaltyFreq: Float = 0.0f,
    val mirostat: Int = 0,            // 0 = disabled, 1 = mirostat, 2 = mirostat 2.0
    val mirostatTau: Float = 5.0f,
    val mirostatEta: Float = 0.1f,
    val stopSequences: List<String> = emptyList(),
    val grammar: String? = null       // GBNF grammar string
)

/**
 * Native generation result
 */
@Serializable
data class GenerationNativeResult(
    val text: String,
    val tokensGenerated: Int,
    val tokensEvaluated: Int,
    val timePromptMs: Long,
    val timeGenerationMs: Long,
    val timeTotalMs: Long,
    val tokensPerSecond: Float,
    val stoppedByLimit: Boolean,
    val stoppedBySequence: String?
)

/**
 * Model information
 */
@Serializable
data class ModelInfo(
    val name: String,
    val type: String,              // e.g., "llama", "mistral", "phi"
    val parameterCount: Long,      // Number of parameters
    val quantization: String,      // e.g., "Q4_K_M", "Q8_0", "F16"
    val fileSize: Long,           // Model file size in bytes
    val contextLength: Int,        // Maximum context length
    val embeddingSize: Int,        // Embedding dimension
    val layerCount: Int,           // Number of layers
    val headCount: Int,            // Number of attention heads
    val vocabSize: Int,            // Vocabulary size
    val isMultilingual: Boolean,
    val isFinetuned: Boolean
)

/**
 * GPU information
 */
@Serializable
data class GpuInfo(
    val deviceName: String,
    val totalMemory: Long,
    val availableMemory: Long,
    val computeCapability: String,
    val supportsFloat16: Boolean,
    val supportsBFloat16: Boolean
)

/**
 * Memory usage statistics
 */
@Serializable
data class MemoryUsage(
    val modelMemory: Long,         // Memory used by model weights
    val contextMemory: Long,       // Memory used by context/KV cache
    val scratchMemory: Long,       // Scratch buffer memory
    val totalMemory: Long,         // Total memory used
    val peakMemory: Long           // Peak memory usage
)
