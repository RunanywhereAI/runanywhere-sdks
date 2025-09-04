package com.runanywhere.runanywhereai.domain.models

/**
 * Represents a chat message in the conversation
 */
data class ChatMessage(
    val id: String,
    val content: String,
    val timestamp: Long,
    val isFromUser: Boolean,
    val thinking: String? = null,
    val analytics: MessageAnalytics? = null
)

/**
 * Analytics information for a message
 * TODO: This will be populated by the SDK's analytics features
 */
data class MessageAnalytics(
    val timeToFirstToken: Long? = null,
    val totalGenerationTime: Long,
    val averageTokensPerSecond: Double,
    val wasThinkingMode: Boolean = false,
    val completionStatus: CompletionStatus,
    val modelUsed: String
)

enum class CompletionStatus {
    SUCCESS, PARTIAL, FAILED, CANCELLED
}
