package com.runanywhere.runanywhereai.ui.screens.chat

import com.runanywhere.runanywhereai.data.conversation.GenerationMode

data class ChatMessage(
    val text: String,
    val isUser: Boolean,
    val thinking: String? = null,
    val attachment: ChatAttachment? = null,
    val sources: List<ChatSource> = emptyList(),
    val stats: GenerationStats? = null,
    val tool: ToolCallInfo? = null,
)

data class ChatAttachment(
    val kind: ChatAttachmentKind,
    val name: String,
    val detail: String? = null,
    val localPath: String? = null,
    val previewText: String? = null,
)

enum class ChatAttachmentKind { IMAGE, DOCUMENT }

data class ChatSource(
    val text: String,
    val score: Float,
    val document: String,
)

// Mirrors the per-message metrics iOS records in MessageAnalytics.
data class GenerationStats(
    val tokens: Int,
    val tokensPerSecond: Double,
    val timeToFirstTokenMs: Long?,
    val totalTimeMs: Long,
    val inputTokens: Int = 0,
    val modelName: String? = null,
    val framework: String? = null,
    val mode: GenerationMode = GenerationMode.STREAMING,
)

data class ToolCallInfo(
    val name: String,
    val arguments: String,
    val result: String?,
    val success: Boolean,
    val error: String?,
)
