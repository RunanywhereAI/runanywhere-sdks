package com.runanywhere.runanywhereai.ui.screens.chat

data class ChatMessage(
    val text: String,
    val isUser: Boolean,
    val thinking: String? = null,
    val stats: GenerationStats? = null,
    val tool: ToolCallInfo? = null,
)

data class GenerationStats(
    val tokens: Int,
    val tokensPerSecond: Double,
    val timeToFirstTokenMs: Long?,
    val totalTimeMs: Long,
)

data class ToolCallInfo(
    val name: String,
    val arguments: String,
    val result: String?,
    val success: Boolean,
    val error: String?,
)
