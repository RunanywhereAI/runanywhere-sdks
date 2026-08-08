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
    /**
     * This turn is a failure report, not something the model said.
     *
     * Mirrors iOS `Message.isError` (Message.swift), and it has to exist for two reasons. A
     * failed turn used to be an ordinary assistant bubble — same ink, same markdown rendering,
     * same Regenerate affordance — so the app attributed its own error text to the model.
     * Worse, `ChatRequestPolicy` fed every non-blank assistant turn back as history, which
     * meant the next request told the model it had previously said "Error: Backend not
     * available for: llm" and it began apologising for a failure it had no part in.
     */
    val isError: Boolean = false,
)

/**
 * The text of a failed turn.
 *
 * `Throwable.message` and `RAError.message` are both nullable, and interpolating them raw
 * produced the bubble "Error: null" — which tells a reader nothing and reads as a bug in the
 * reply rather than a failure to produce one. One helper so every failure site in
 * `ChatViewModel` words it the same way.
 */
fun errorReplyText(detail: String?): String {
    val explanation = detail?.takeIf { it.isNotBlank() } ?: "the reply could not be generated"
    return "Error: $explanation"
}

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
