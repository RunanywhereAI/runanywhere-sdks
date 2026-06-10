package com.runanywhere.runanywhereai.data.conversation

import kotlinx.serialization.Serializable

@Serializable
data class StoredConversation(
    val id: String,
    val title: String,
    val createdAt: Long,
    val updatedAt: Long,
    val pinned: Boolean = false,
    val messages: List<StoredMessage>,
)

@Serializable
data class StoredMessage(
    val text: String,
    val isUser: Boolean,
    val thinking: String? = null,
    val tool: StoredTool? = null,
    val stats: StoredStats? = null,
)

@Serializable
data class StoredTool(
    val name: String,
    val arguments: String,
    val result: String? = null,
    val success: Boolean,
    val error: String? = null,
)

@Serializable
data class StoredStats(
    val tokens: Int,
    val tokensPerSecond: Double,
    val timeToFirstTokenMs: Long? = null,
    val totalTimeMs: Long,
)

data class ConversationSummary(
    val id: String,
    val title: String,
    val updatedAt: Long,
    val preview: String,
    val pinned: Boolean,
)
