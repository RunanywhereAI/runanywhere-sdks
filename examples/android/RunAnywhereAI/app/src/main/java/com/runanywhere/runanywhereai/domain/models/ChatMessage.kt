package com.runanywhere.runanywhereai.domain.models

import java.util.*

/**
 * Represents a chat message in the conversation
 * Enhanced to match iOS Message functionality with comprehensive analytics
 */
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,
    val content: String,
    val thinkingContent: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val analytics: MessageAnalytics? = null,
    val modelInfo: MessageModelInfo? = null
) {
    val isFromUser: Boolean get() = role == MessageRole.USER
}

/**
 * Message role types matching iOS implementation
 */
enum class MessageRole {
    SYSTEM, USER, ASSISTANT
}

/**
 * Model information for each message
 */
data class MessageModelInfo(
    val modelId: String,
    val modelName: String,
    val framework: String
)

/**
 * Comprehensive analytics information matching iOS MessageAnalytics
 * Tracks detailed performance metrics for AI generation
 */
data class MessageAnalytics(
    // Identifiers
    val messageId: String,
    val conversationId: String,
    val modelId: String,
    val modelName: String,
    val framework: String,
    val timestamp: Long,

    // Timing Metrics
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
)

/**
 * Completion status for messages
 */
enum class CompletionStatus {
    COMPLETE,
    INTERRUPTED,
    FAILED,
    TIMEOUT
}

/**
 * Generation mode (streaming vs non-streaming)
 */
enum class GenerationMode {
    STREAMING,
    NON_STREAMING
}

/**
 * Generation parameters used for the message
 */
data class GenerationParameters(
    val temperature: Double = 0.7,
    val maxTokens: Int = 500,
    val topP: Double? = null,
    val topK: Int? = null
)

/**
 * Conversation analytics aggregating message metrics
 */
data class ConversationAnalytics(
    val conversationId: String,
    val startTime: Long,
    val endTime: Long? = null,
    val messageCount: Int,

    // Aggregate Metrics
    val averageTTFT: Double,
    val averageGenerationSpeed: Double,
    val totalTokensUsed: Int,
    val modelsUsed: Set<String>,

    // Efficiency Metrics
    val thinkingModeUsage: Double, // percentage
    val completionRate: Double, // successful / total
    val averageMessageLength: Int,

    // Real-time Metrics
    val currentModel: String? = null,
    val ongoingMetrics: MessageAnalytics? = null
)

/**
 * Performance summary for conversations
 */
data class PerformanceSummary(
    val totalMessages: Int,
    val averageResponseTime: Double,
    val averageTokensPerSecond: Double,
    val totalTokensProcessed: Int,
    val thinkingModeUsage: Double,
    val successRate: Double
) {
    companion object {
        fun from(messages: List<ChatMessage>): PerformanceSummary {
            val analyticsMessages = messages.mapNotNull { it.analytics }

            return PerformanceSummary(
                totalMessages = messages.size,
                averageResponseTime = if (analyticsMessages.isNotEmpty()) {
                    analyticsMessages.map { it.totalGenerationTime }.average() / 1000.0
                } else 0.0,
                averageTokensPerSecond = if (analyticsMessages.isNotEmpty()) {
                    analyticsMessages.map { it.averageTokensPerSecond }.average()
                } else 0.0,
                totalTokensProcessed = analyticsMessages.sumOf { it.inputTokens + it.outputTokens },
                thinkingModeUsage = if (analyticsMessages.isNotEmpty()) {
                    analyticsMessages.count { it.wasThinkingMode }.toDouble() / analyticsMessages.size
                } else 0.0,
                successRate = if (analyticsMessages.isNotEmpty()) {
                    analyticsMessages.count { it.completionStatus == CompletionStatus.COMPLETE }.toDouble() / analyticsMessages.size
                } else 0.0
            )
        }
    }
}

/**
 * Conversation data class for persistence
 */
data class Conversation(
    val id: String = UUID.randomUUID().toString(),
    val title: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val modelName: String? = null,
    val analytics: ConversationAnalytics? = null,
    val performanceSummary: PerformanceSummary? = null
)
