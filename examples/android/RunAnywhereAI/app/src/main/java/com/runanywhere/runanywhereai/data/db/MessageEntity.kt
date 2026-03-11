package com.runanywhere.runanywhereai.data.db

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "messages",
    foreignKeys = [
        ForeignKey(
            entity = ConversationEntity::class,
            parentColumns = ["id"],
            childColumns = ["conversationId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("conversationId")],
)
data class MessageEntity(
    @PrimaryKey val id: String,
    val conversationId: String,
    val role: String,
    val content: String,
    val thinkingContent: String?,
    val timestamp: Long,
    val tokensPerSecond: Double?,
    val totalGenerationTime: Long?,
    val timeToFirstToken: Long?,
    val inputTokens: Int?,
    val outputTokens: Int?,
    val modelId: String?,
    val modelName: String?,
    val modelFramework: String?,
    val isError: Boolean = false,
)
