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
    // Mirrors iOS Conversation.modelName (ConversationStore.swift:296): the model
    // that produced the latest reply, restored as a preselection when reopening.
    val modelName: String? = null,
    // Claimed before hidden title inference starts, so failures/cancellation do
    // not silently repeat model work on every subsequent save or app launch.
    val smartTitleAttempted: Boolean = false,
)

@Serializable
data class StoredMessage(
    val text: String,
    val isUser: Boolean,
    val thinking: String? = null,
    val attachment: StoredAttachment? = null,
    val sources: List<StoredSource> = emptyList(),
    val tool: StoredTool? = null,
    val stats: StoredStats? = null,
)

@Serializable
data class StoredAttachment(
    val kind: StoredAttachmentKind,
    val name: String,
    val detail: String? = null,
    val localPath: String? = null,
    val previewText: String? = null,
)

@Serializable
enum class StoredAttachmentKind { IMAGE, DOCUMENT }

@Serializable
data class StoredSource(
    val text: String,
    val score: Float,
    val document: String,
)

@Serializable
data class StoredTool(
    val name: String,
    val arguments: String,
    val result: String? = null,
    val success: Boolean,
    val error: String? = null,
)

// Mirrors the metrics iOS persists per message in MessageAnalytics.
@Serializable
data class StoredStats(
    val tokens: Int,
    val tokensPerSecond: Double,
    val timeToFirstTokenMs: Long? = null,
    val totalTimeMs: Long,
    val inputTokens: Int = 0,
    val modelName: String? = null,
    val framework: String? = null,
    val mode: GenerationMode = GenerationMode.STREAMING,
)

@Serializable
enum class GenerationMode { STREAMING, NON_STREAMING }

data class ConversationSummary(
    val id: String,
    val title: String,
    val updatedAt: Long,
    val preview: String,
    val pinned: Boolean,
    // Context snippet around the matched message text when a search query
    // matched message content rather than the title (iOS ConversationRow).
    val matchPreview: String? = null,
)
