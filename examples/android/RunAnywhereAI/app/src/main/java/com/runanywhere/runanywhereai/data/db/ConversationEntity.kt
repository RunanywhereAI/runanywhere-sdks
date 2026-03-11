package com.runanywhere.runanywhereai.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "conversations")
data class ConversationEntity(
    @PrimaryKey val id: String,
    val title: String?,
    val modelName: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val messageCount: Int,
)
