package com.runanywhere.runanywhereai.domain.models

import com.runanywhere.sdk.models.Message
import kotlinx.serialization.Serializable
import java.util.UUID
import com.runanywhere.sdk.models.CompletionStatus as SDKCompletionStatus
import com.runanywhere.sdk.models.ConversationAnalytics as SDKConversationAnalytics
import com.runanywhere.sdk.models.GenerationMode as SDKGenerationMode
import com.runanywhere.sdk.models.GenerationParameters as SDKGenerationParameters
import com.runanywhere.sdk.models.MessageAnalytics as SDKMessageAnalytics
import com.runanywhere.sdk.models.MessageModelInfo as SDKMessageModelInfo
import com.runanywhere.sdk.models.MessageRole as SDKMessageRole
import com.runanywhere.sdk.models.PerformanceSummary as SDKPerformanceSummary

// Re-export SDK types for use throughout the app
typealias MessageRole = SDKMessageRole
typealias MessageAnalytics = SDKMessageAnalytics
typealias MessageModelInfo = SDKMessageModelInfo
typealias CompletionStatus = SDKCompletionStatus
typealias GenerationMode = SDKGenerationMode
typealias GenerationParameters = SDKGenerationParameters
typealias ConversationAnalytics = SDKConversationAnalytics
typealias PerformanceSummary = SDKPerformanceSummary

/**
 * App-specific wrapper for SDK Message that adds an id field
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

    fun toSDKMessage(): Message =
        Message(
            role = role,
            content = content,
            thinkingContent = thinkingContent,
            metadata = metadata,
            timestamp = timestamp,
            analytics = analytics,
            modelInfo = modelInfo,
        )

    companion object {
        fun fromSDKMessage(
            message: Message,
            id: String = UUID.randomUUID().toString(),
        ): ChatMessage =
            ChatMessage(
                id = id,
                role = message.role,
                content = message.content,
                thinkingContent = message.thinkingContent,
                timestamp = message.timestamp,
                analytics = message.analytics,
                modelInfo = message.modelInfo,
                metadata = message.metadata,
            )
    }
}

/**
 * App-specific Conversation that uses ChatMessage instead of Message
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

    return SDKPerformanceSummary(
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
                0.0
            },
    )
}
