package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
@Immutable
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,
    val content: String,
    val thinkingContent: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val analytics: MessageAnalytics? = null,
    val modelInfo: MessageModelInfo? = null,
) {
    val isFromUser: Boolean get() = role == MessageRole.USER
    val isFromAssistant: Boolean get() = role == MessageRole.ASSISTANT
    val isSystem: Boolean get() = role == MessageRole.SYSTEM

    companion object {
        fun user(content: String): ChatMessage =
            ChatMessage(role = MessageRole.USER, content = content)

        fun assistant(
            content: String,
            thinkingContent: String? = null,
            analytics: MessageAnalytics? = null,
            modelInfo: MessageModelInfo? = null,
        ): ChatMessage =
            ChatMessage(
                role = MessageRole.ASSISTANT,
                content = content,
                thinkingContent = thinkingContent,
                analytics = analytics,
                modelInfo = modelInfo,
            )

        fun system(content: String): ChatMessage =
            ChatMessage(role = MessageRole.SYSTEM, content = content)
    }
}

@Serializable
enum class MessageRole {
    USER,
    ASSISTANT,
    SYSTEM,
    ;

    val displayName: String
        get() = when (this) {
            USER -> "User"
            ASSISTANT -> "Assistant"
            SYSTEM -> "System"
        }
}
