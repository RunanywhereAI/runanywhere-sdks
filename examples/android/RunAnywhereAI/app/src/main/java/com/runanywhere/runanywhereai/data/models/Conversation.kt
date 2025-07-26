package com.runanywhere.runanywhereai.data.models

import com.runanywhere.runanywhereai.data.database.ConversationEntity
import com.runanywhere.runanywhereai.data.database.MessageEntity
import java.time.Instant

data class Conversation(
    val id: String,
    val title: String,
    val createdAt: Instant,
    val updatedAt: Instant,
    val framework: String,
    val modelName: String,
    val messageCount: Int = 0,
    val totalTokens: Int = 0
)

data class Message(
    val id: String,
    val conversationId: String,
    val role: String,
    val content: String,
    val timestamp: Instant,
    val tokenCount: Int = 0,
    val generationTimeMs: Long? = null
)

// Extension functions for mapping
fun ConversationEntity.toConversation(): Conversation {
    return Conversation(
        id = id,
        title = title,
        createdAt = createdAt,
        updatedAt = updatedAt,
        framework = framework,
        modelName = modelName,
        messageCount = messageCount,
        totalTokens = totalTokens
    )
}

fun MessageEntity.toMessage(): Message {
    return Message(
        id = id,
        conversationId = conversationId,
        role = role,
        content = content,
        timestamp = timestamp,
        tokenCount = tokenCount,
        generationTimeMs = generationTimeMs
    )
}