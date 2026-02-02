package com.runanywhere.runanywhereai.domain.models

import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * App-local message role enum.
 * Matches iOS MessageRole exactly.
 */
@Serializable
enum class MessageRole {
    USER,
    ASSISTANT,
    SYSTEM,
    ;

    val displayName: String
        get() =
            when (this) {
                USER -> "User"
                ASSISTANT -> "Assistant"
                SYSTEM -> "System"
            }
}

/**
 * App-local completion status enum.
 * Matches iOS CompletionStatus exactly.
 */
@Serializable
enum class CompletionStatus {
    COMPLETE,
    STREAMING,
    INTERRUPTED,
    ERROR,
}

/**
 * App-local generation mode enum.
 * Matches iOS GenerationMode exactly.
 */
@Serializable
enum class GenerationMode {
    STREAMING,
    NON_STREAMING,
}

/**
 * App-local generation parameters.
 * Matches iOS GenerationParameters exactly.
 */
@Serializable
data class GenerationParameters(
    val temperature: Float = 0.7f,
    val maxTokens: Int = 2048,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val enableThinking: Boolean = false,
)

/**
 * App-local model info for messages.
 * Matches iOS MessageModelInfo exactly.
 */
@Serializable
data class MessageModelInfo(
    val modelId: String,
    val modelName: String,
    val framework: String? = null,
)

/**
 * App-local message analytics.
 * Matches iOS MessageAnalytics exactly.
 */
@Serializable
data class MessageAnalytics(
    /** When the message was generated */
    val timestamp: Long = System.currentTimeMillis(),
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    /** Total generation time in milliseconds */
    val totalGenerationTime: Long = 0,
    /** Time to first token in milliseconds (nullable since not always available) */
    val timeToFirstToken: Long? = null,
    val averageTokensPerSecond: Double = 0.0,
    val wasThinkingMode: Boolean = false,
    val completionStatus: CompletionStatus = CompletionStatus.COMPLETE,
)

/**
 * App-local conversation analytics.
 * Matches iOS ConversationAnalytics exactly.
 */
@Serializable
data class ConversationAnalytics(
    val totalMessages: Int = 0,
    val totalTokens: Int = 0,
    /** Total duration in milliseconds */
    val totalDuration: Long = 0,
)

/**
 * App-local performance summary.
 * Matches iOS PerformanceSummary exactly.
 */
@Serializable
data class PerformanceSummary(
    val totalMessages: Int = 0,
    /** Average response time in seconds */
    val averageResponseTime: Double = 0.0,
    val averageTokensPerSecond: Double = 0.0,
    val totalTokensProcessed: Int = 0,
    /** Thinking mode usage ratio (0-1) */
    val thinkingModeUsage: Double = 0.0,
    /** Success rate ratio (0-1) */
    val successRate: Double = 1.0,
)

/**
 * App-specific ChatMessage for conversations.
 * Self-contained with app-local types.
 */
@Serializable
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,
    val content: String,
    val thinkingContent: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val analytics: MessageAnalytics? = null,
    val modelInfo: MessageModelInfo? = null,
    val metadata: Map<String, String>? = null,
) {
    val isFromUser: Boolean get() = role == MessageRole.USER
    val isFromAssistant: Boolean get() = role == MessageRole.ASSISTANT
    val isSystem: Boolean get() = role == MessageRole.SYSTEM

    companion object {
        /**
         * Create a user message
         */
        fun user(
            content: String,
            metadata: Map<String, String>? = null,
        ): ChatMessage =
            ChatMessage(
                role = MessageRole.USER,
                content = content,
                metadata = metadata,
            )

        /**
         * Create an assistant message
         */
        fun assistant(
            content: String,
            thinkingContent: String? = null,
            analytics: MessageAnalytics? = null,
            modelInfo: MessageModelInfo? = null,
            metadata: Map<String, String>? = null,
        ): ChatMessage =
            ChatMessage(
                role = MessageRole.ASSISTANT,
                content = content,
                thinkingContent = thinkingContent,
                analytics = analytics,
                modelInfo = modelInfo,
                metadata = metadata,
            )

        /**
         * Create a system message
         */
        fun system(content: String): ChatMessage =
            ChatMessage(
                role = MessageRole.SYSTEM,
                content = content,
            )
    }
}

/**
 * App-specific Conversation that uses ChatMessage
 */
@Serializable
data class Conversation(
    val id: String,
    val title: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val modelName: String? = null,
    val analytics: ConversationAnalytics? = null,
    val performanceSummary: PerformanceSummary? = null,
)

/**
 * Helper function to create PerformanceSummary from messages
 */
fun createPerformanceSummary(messages: List<ChatMessage>): PerformanceSummary {
    val analyticsMessages = messages.mapNotNull { it.analytics }

    return PerformanceSummary(
        totalMessages = messages.size,
        averageResponseTime =
            if (analyticsMessages.isNotEmpty()) {
                analyticsMessages.map { it.totalGenerationTime }.average() / 1000.0
            } else {
                0.0
            },
        averageTokensPerSecond =
            if (analyticsMessages.isNotEmpty()) {
                analyticsMessages.map { it.averageTokensPerSecond }.average()
            } else {
                0.0
            },
        totalTokensProcessed = analyticsMessages.sumOf { it.inputTokens + it.outputTokens },
        thinkingModeUsage =
            if (analyticsMessages.isNotEmpty()) {
                analyticsMessages.count { it.wasThinkingMode }.toDouble() / analyticsMessages.size
            } else {
                0.0
            },
        successRate =
            if (analyticsMessages.isNotEmpty()) {
                analyticsMessages.count { it.completionStatus == CompletionStatus.COMPLETE }
                    .toDouble() / analyticsMessages.size
            } else {
                1.0
            },
    )
}
