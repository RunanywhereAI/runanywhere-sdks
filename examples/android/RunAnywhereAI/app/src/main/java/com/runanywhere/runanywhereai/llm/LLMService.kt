package com.runanywhere.runanywhereai.llm

import kotlinx.coroutines.flow.Flow

/**
 * Base interface for all LLM service implementations
 * 
 * This interface provides a unified API for interacting with different LLM frameworks
 * including MediaPipe, ONNX Runtime, TensorFlow Lite, llama.cpp, ExecuTorch, MLC-LLM, 
 * Gemini Nano, Android AI Core, and picoLLM.
 * 
 * All implementations should handle model loading, text generation, and resource cleanup
 * in a consistent manner while abstracting away framework-specific details.
 * 
 * @sample Basic usage:
 * ```kotlin
 * val service = MediaPipeService(context)
 * service.initialize("/path/to/model.bin")
 * val result = service.generate("Hello, world!", GenerationOptions())
 * println("Generated: ${result.text}")
 * service.release()
 * ```
 */
interface LLMService {
    val name: String
    val isInitialized: Boolean
    
    /**
     * Initialize the LLM service with a model
     * 
     * @param modelPath Path to the model file (format depends on framework)
     * @throws IllegalArgumentException if model path is invalid
     * @throws IllegalStateException if initialization fails
     */
    suspend fun initialize(modelPath: String)
    
    /**
     * Generate text based on the prompt
     * 
     * @param prompt Input text to generate from
     * @param options Generation parameters (temperature, max tokens, etc.)
     * @return GenerationResult containing generated text and performance metrics
     * @throws IllegalStateException if service is not initialized
     */
    suspend fun generate(prompt: String, options: GenerationOptions = GenerationOptions()): GenerationResult
    
    /**
     * Stream generation results token by token
     * 
     * This method provides real-time streaming of generated text, useful for
     * displaying incremental results to users as they are generated.
     * 
     * @param prompt Input text to generate from
     * @param options Generation parameters
     * @return Flow of GenerationResult objects with partial text and cumulative metrics
     * @throws IllegalStateException if service is not initialized
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