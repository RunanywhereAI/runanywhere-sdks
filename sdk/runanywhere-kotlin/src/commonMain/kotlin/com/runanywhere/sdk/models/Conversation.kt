package com.runanywhere.sdk.models

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

// MARK: - Message

/**
 * A message in a conversation - exact match with iOS Message structure
 * Enhanced with optional analytics and model info for tracking
 */
@Serializable
data class Message(
    /** The role of the message sender */
    val role: MessageRole,

    /** The content of the message */
    val content: String,

    /** Optional thinking content (for thinking mode models) */
    val thinkingContent: String? = null,

    /** Optional metadata */
    val metadata: Map<String, String>? = null,

    /** Timestamp when the message was created */
    val timestamp: Long = getCurrentTimeMillis(),

    /** Optional analytics data for this message */
    val analytics: MessageAnalytics? = null,

    /** Optional model information for this message */
    val modelInfo: MessageModelInfo? = null
) {
    /** Helper to check if message is from user */
    val isFromUser: Boolean get() = role == MessageRole.USER
}

// MARK: - Message Role

/**
 * Role of the message sender - exact match with iOS MessageRole
 */
@Serializable
enum class MessageRole(val value: String) {
    SYSTEM("system"),
    USER("user"),
    ASSISTANT("assistant");

    companion object {
        fun fromValue(value: String): MessageRole? {
            return values().find { it.value == value }
        }
    }
}

// MARK: - Context

/**
 * Context for a conversation - exact match with iOS Context structure
 */
@Serializable
data class Context(
    /** System prompt for the conversation */
    val systemPrompt: String? = null,

    /** Previous messages in the conversation */
    val messages: List<Message> = emptyList(),

    /** Maximum number of messages to keep in context */
    val maxMessages: Int = 100,

    /** Additional context metadata */
    val metadata: Map<String, String> = emptyMap()
) {
    /**
     * Add a message to the context
     */
    fun adding(message: Message): Context {
        val newMessages = messages.toMutableList()
        newMessages.add(message)

        // Trim if exceeds max
        val trimmedMessages = if (newMessages.size > maxMessages) {
            newMessages.takeLast(maxMessages)
        } else {
            newMessages
        }

        return copy(messages = trimmedMessages)
    }

    /**
     * Clear all messages but keep system prompt
     */
    fun cleared(): Context {
        return copy(
            messages = emptyList(),
            metadata = metadata
        )
    }

    /**
     * Get total message count
     */
    val messageCount: Int
        get() = messages.size

    /**
     * Check if context is empty
     */
    val isEmpty: Boolean
        get() = messages.isEmpty() && systemPrompt == null

    /**
     * Get context length estimate (for token counting)
     */
    fun getEstimatedTokenCount(): Int {
        var tokenCount = 0

        systemPrompt?.let { tokenCount += it.length / 4 }

        for (message in messages) {
            tokenCount += message.content.length / 4
        }

        return tokenCount
    }
}

// MARK: - Conversation

/**
 * Conversation data class for persistence
 * Enhanced with analytics and performance tracking
 */
@Serializable
data class Conversation(
    val id: String,
    val title: String? = null,
    val messages: List<Message> = emptyList(),
    val createdAt: Long = getCurrentTimeMillis(),
    val updatedAt: Long = getCurrentTimeMillis(),
    val modelName: String? = null,
    val analytics: ConversationAnalytics? = null,
    val performanceSummary: PerformanceSummary? = null
)
