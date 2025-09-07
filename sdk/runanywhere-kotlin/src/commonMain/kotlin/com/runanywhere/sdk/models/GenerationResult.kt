package com.runanywhere.sdk.models

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

/**
 * Token usage information - exact match with iOS TokenUsage
 */
@Serializable
data class TokenUsage(
    /** Number of tokens in the prompt */
    val promptTokens: Int,

    /** Number of tokens in the completion */
    val completionTokens: Int
) {
    /** Total tokens used (prompt + completion) */
    val totalTokens: Int
        get() = promptTokens + completionTokens

    /**
     * Validate token counts
     */
    fun validate() {
        require(promptTokens >= 0) { "Prompt tokens must be non-negative" }
        require(completionTokens >= 0) { "Completion tokens must be non-negative" }
    }
}

/**
 * Generation metadata - exact match with iOS GenerationMetadata
 */
@Serializable
data class GenerationMetadata(
    /** Model identifier used for generation */
    val modelId: String,

    /** Temperature used for generation */
    val temperature: Float,

    /** Generation time in milliseconds */
    val generationTime: Long,

    /** Tokens per second (performance metric) */
    val tokensPerSecond: Double? = null,

    /** Additional metadata */
    val additionalInfo: Map<String, String> = emptyMap()
) {
    /**
     * Validate metadata
     */
    fun validate() {
        require(temperature >= 0f && temperature <= 2f) { "Temperature must be between 0 and 2" }
        require(generationTime >= 0) { "Generation time must be non-negative" }
        tokensPerSecond?.let { require(it >= 0.0) { "Tokens per second must be non-negative" } }
    }

    /**
     * Create a copy with additional info
     */
    fun withAdditionalInfo(key: String, value: String): GenerationMetadata {
        return copy(additionalInfo = additionalInfo + (key to value))
    }
}

/**
 * Reason for generation completion - exact match with iOS FinishReason
 */
@Serializable
enum class FinishReason(val value: String) {
    /** Generation completed normally */
    COMPLETED("completed"),

    /** Maximum tokens reached */
    MAX_TOKENS("max_tokens"),

    /** Stop sequence encountered */
    STOP_SEQUENCE("stop_sequence"),

    /** Content filtered */
    CONTENT_FILTER("content_filter"),

    /** Error occurred */
    ERROR("error"),

    /** Generation was cancelled */
    CANCELLED("cancelled");

    companion object {
        fun fromValue(value: String): FinishReason? {
            return values().find { it.value == value }
        }
    }
}

/**
 * Enhanced generation result with comprehensive metadata and token tracking
 * Combines aspects of both iOS LLMOutput and Kotlin GenerationResult
 */
@Serializable
data class LLMGenerationResult(
    /** Generated text */
    val text: String,

    /** Token usage statistics */
    val tokenUsage: TokenUsage,

    /** Generation metadata */
    val metadata: GenerationMetadata,

    /** Finish reason */
    val finishReason: FinishReason,

    /** Timestamp when generation completed */
    val timestamp: Long = getCurrentTimeMillis(),

    /** Session ID for tracking */
    val sessionId: String? = null,

    /** Cost savings compared to cloud execution */
    val savedAmount: Double = 0.0,

    /** Execution target that was actually used */
    val actualExecutionTarget: ExecutionTarget? = null
) {
    /**
     * Validate the result
     */
    fun validate() {
        require(text.isNotEmpty() || finishReason == FinishReason.ERROR) {
            "Text must not be empty unless generation failed"
        }
        tokenUsage.validate()
        metadata.validate()
        require(timestamp > 0) { "Timestamp must be positive" }
        require(savedAmount >= 0.0) { "Saved amount must be non-negative" }
    }

    /**
     * Check if generation was successful
     */
    val isSuccessful: Boolean
        get() = finishReason == FinishReason.COMPLETED || finishReason == FinishReason.MAX_TOKENS || finishReason == FinishReason.STOP_SEQUENCE

    /**
     * Get effective tokens per second
     */
    val effectiveTokensPerSecond: Double?
        get() = metadata.tokensPerSecond ?: if (metadata.generationTime > 0) {
            tokenUsage.completionTokens.toDouble() / (metadata.generationTime / 1000.0)
        } else null
}

/**
 * Generation chunk for streaming - enhanced with metadata
 */
@Serializable
data class LLMGenerationChunk(
    /** Text chunk */
    val text: String,

    /** Whether this is the final chunk */
    val isComplete: Boolean = false,

    /** Token count for this chunk */
    val tokenCount: Int = 0,

    /** Timestamp for this chunk */
    val timestamp: Long = getCurrentTimeMillis(),

    /** Chunk index in the stream */
    val chunkIndex: Int = 0,

    /** Session ID for tracking */
    val sessionId: String? = null,

    /** Finish reason if this is the final chunk */
    val finishReason: FinishReason? = null
) {
    /**
     * Validate the chunk
     */
    fun validate() {
        require(tokenCount >= 0) { "Token count must be non-negative" }
        require(timestamp > 0) { "Timestamp must be positive" }
        require(chunkIndex >= 0) { "Chunk index must be non-negative" }
        if (isComplete) {
            require(finishReason != null) { "Final chunk must have a finish reason" }
        }
    }
}
