package com.runanywhere.runanywhereai.llm

import kotlinx.coroutines.flow.Flow

/**
 * Base interface for all LLM service implementations
 */
interface LLMService {
    val name: String
    val isInitialized: Boolean
    
    /**
     * Initialize the LLM service with a model
     */
    suspend fun initialize(modelPath: String)
    
    /**
     * Generate text based on the prompt
     */
    suspend fun generate(prompt: String, options: GenerationOptions = GenerationOptions()): GenerationResult
    
    /**
     * Stream generation results token by token
     */
    fun generateStream(prompt: String, options: GenerationOptions = GenerationOptions()): Flow<GenerationResult>
    
    /**
     * Get information about the loaded model
     */
    fun getModelInfo(): ModelInfo?
    
    /**
     * Release resources
     */
    suspend fun release()
}

/**
 * Options for text generation
 */
data class GenerationOptions(
    val maxTokens: Int = 150,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repetitionPenalty: Float = 1.1f,
    val stopSequences: List<String> = emptyList(),
    val presencePenalty: Float? = null,
    val frequencyPenalty: Float? = null
)

/**
 * Information about the loaded model
 */
data class ModelInfo(
    val name: String,
    val sizeBytes: Long,
    val parameters: Long? = null,
    val quantization: String? = null,
    val format: String,
    val framework: LLMFramework
)

/**
 * Supported LLM frameworks
 */
enum class LLMFramework {
    MEDIAPIPE,
    ONNX_RUNTIME,
    TFLITE,
    LLAMA_CPP,
    EXECUTORCH,
    MLC_LLM,
    GEMINI_NANO,
    PICOLLM,
    AI_CORE
}

/**
 * Chat message for conversation
 */
data class ChatMessage(
    val role: ChatRole,
    val content: String,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Chat roles
 */
enum class ChatRole {
    USER, ASSISTANT, SYSTEM
}

/**
 * Reason why generation finished
 */
enum class FinishReason {
    COMPLETED,
    MAX_TOKENS,
    STOP_SEQUENCE,
    ERROR,
    CANCELLED
}

/**
 * Performance metrics for generation
 */
data class PerformanceMetrics(
    val totalTime: Long,
    val timeToFirstToken: Long,
    val tokensPerSecond: Float,
    val tokenCount: Int,
    val memoryUsed: Long,
    val cpuUsage: Float? = null,
    val batteryTemperature: Float? = null
)