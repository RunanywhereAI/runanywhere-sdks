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

/**
 * Completion status for messages
 * Matches iOS MessageAnalytics.CompletionStatus
 */
@Serializable
enum class CompletionStatus(val value: String) {
    COMPLETE("complete"),
    INTERRUPTED("interrupted"),
    FAILED("failed"),
    TIMEOUT("timeout");

    companion object {
        fun fromValue(value: String): CompletionStatus? {
            return values().find { it.value == value }
        }
    }
}

/**
 * Generation mode (streaming vs non-streaming)
 * Matches iOS MessageAnalytics.GenerationMode
 */
@Serializable
enum class GenerationMode(val value: String) {
    STREAMING("streaming"),
    NON_STREAMING("nonStreaming");

    companion object {
        fun fromValue(value: String): GenerationMode? {
            return values().find { it.value == value }
        }
    }
}

/**
 * Generation parameters used for a message
 * Matches iOS MessageAnalytics.GenerationParameters
 */
@Serializable
data class GenerationParameters(
    val temperature: Double = 0.7,
    val maxTokens: Int = 500,
    val topP: Double? = null,
    val topK: Int? = null
)

/**
 * Comprehensive analytics information for message generation
 * Tracks detailed performance metrics for AI generation
 * Matches iOS MessageAnalytics structure
 */
@Serializable
data class MessageAnalytics(
    // Identifiers
    val messageId: String,
    val conversationId: String,
    val modelId: String,
    val modelName: String,
    val framework: com.runanywhere.sdk.models.enums.LLMFramework,
    val timestamp: Long,

    // Timing Metrics (in milliseconds)
    val timeToFirstToken: Long? = null,
    val totalGenerationTime: Long,
    val thinkingTime: Long? = null,
    val responseTime: Long? = null,

    // Token Metrics
    val inputTokens: Int,
    val outputTokens: Int,
    val thinkingTokens: Int? = null,
    val responseTokens: Int,
    val averageTokensPerSecond: Double,

    // Quality Metrics
    val messageLength: Int,
    val wasThinkingMode: Boolean = false,
    val wasInterrupted: Boolean = false,
    val retryCount: Int = 0,
    val completionStatus: CompletionStatus,

    // Performance Indicators
    val tokensPerSecondHistory: List<Double> = emptyList(),
    val generationMode: GenerationMode,

    // Context Information
    val contextWindowUsage: Double = 0.0,
    val generationParameters: GenerationParameters
) {
    /**
     * Validate analytics data
     */
    fun validate() {
        require(timestamp > 0) { "Timestamp must be positive" }
        require(totalGenerationTime >= 0) { "Total generation time must be non-negative" }
        require(inputTokens >= 0) { "Input tokens must be non-negative" }
        require(outputTokens >= 0) { "Output tokens must be non-negative" }
        require(responseTokens >= 0) { "Response tokens must be non-negative" }
        require(averageTokensPerSecond >= 0) { "Average tokens per second must be non-negative" }
        require(messageLength >= 0) { "Message length must be non-negative" }
        require(contextWindowUsage >= 0.0 && contextWindowUsage <= 1.0) {
            "Context window usage must be between 0 and 1"
        }
    }
}

/**
 * Model information for a message
 * Simple reference to the model used for generation
 */
@Serializable
data class MessageModelInfo(
    val modelId: String,
    val modelName: String,
    val framework: com.runanywhere.sdk.models.enums.LLMFramework
)

/**
 * Conversation analytics aggregating message metrics
 * Matches iOS ConversationAnalytics structure
 */
@Serializable
data class ConversationAnalytics(
    val conversationId: String,
    val startTime: Long,
    val endTime: Long? = null,
    val messageCount: Int,

    // Aggregate Metrics (timing in milliseconds, speed in tokens/sec)
    val averageTTFT: Double,
    val averageGenerationSpeed: Double,
    val totalTokensUsed: Int,
    val modelsUsed: Set<String>,

    // Efficiency Metrics (percentages as doubles 0.0-1.0)
    val thinkingModeUsage: Double,
    val completionRate: Double,
    val averageMessageLength: Int,

    // Real-time Metrics
    val currentModel: String? = null,
    val ongoingMetrics: MessageAnalytics? = null
) {
    /**
     * Validate conversation analytics
     */
    fun validate() {
        require(startTime > 0) { "Start time must be positive" }
        endTime?.let { require(it >= startTime) { "End time must be after start time" } }
        require(messageCount >= 0) { "Message count must be non-negative" }
        require(averageTTFT >= 0) { "Average TTFT must be non-negative" }
        require(averageGenerationSpeed >= 0) { "Average generation speed must be non-negative" }
        require(totalTokensUsed >= 0) { "Total tokens used must be non-negative" }
        require(thinkingModeUsage >= 0.0 && thinkingModeUsage <= 1.0) {
            "Thinking mode usage must be between 0 and 1"
        }
        require(completionRate >= 0.0 && completionRate <= 1.0) {
            "Completion rate must be between 0 and 1"
        }
        require(averageMessageLength >= 0) { "Average message length must be non-negative" }
    }
}

/**
 * Performance summary for conversations
 * Provides high-level metrics across all messages
 * Matches iOS PerformanceSummary structure
 */
@Serializable
data class PerformanceSummary(
    val totalMessages: Int,
    val averageResponseTime: Double, // in seconds
    val averageTokensPerSecond: Double,
    val totalTokensProcessed: Int,
    val thinkingModeUsage: Double, // percentage as 0.0-1.0
    val successRate: Double // percentage as 0.0-1.0
) {
    /**
     * Validate performance summary
     */
    fun validate() {
        require(totalMessages >= 0) { "Total messages must be non-negative" }
        require(averageResponseTime >= 0) { "Average response time must be non-negative" }
        require(averageTokensPerSecond >= 0) { "Average tokens per second must be non-negative" }
        require(totalTokensProcessed >= 0) { "Total tokens processed must be non-negative" }
        require(thinkingModeUsage >= 0.0 && thinkingModeUsage <= 1.0) {
            "Thinking mode usage must be between 0 and 1"
        }
        require(successRate >= 0.0 && successRate <= 1.0) {
            "Success rate must be between 0 and 1"
        }
    }
}
