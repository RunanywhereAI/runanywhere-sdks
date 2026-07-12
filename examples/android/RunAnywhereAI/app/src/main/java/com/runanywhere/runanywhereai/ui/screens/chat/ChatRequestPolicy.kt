package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ChatMessage as ProtoChatMessage
import ai.runanywhere.proto.v1.MessageRole
import com.runanywhere.sdk.public.extensions.toRALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions

internal data class ChatTurnSnapshot(
    val prompt: String,
    val history: List<ProtoChatMessage>,
)

/** Pure request construction kept separate from Android lifecycle ownership. */
internal object ChatRequestPolicy {
    /**
     * Snapshot completed turns before the caller appends the current prompt.
     * Blank assistant placeholders and cancelled blank turns are not history.
     */
    fun snapshot(prompt: String, messages: List<ChatMessage>): ChatTurnSnapshot =
        ChatTurnSnapshot(
            prompt = prompt,
            history = messages.mapNotNull(::toProtoMessage),
        )

    fun buildRequest(
        turn: ChatTurnSnapshot,
        options: RALLMGenerationOptions,
        conversationId: String,
        streaming: Boolean,
    ): RALLMGenerateRequest =
        options.copy(
            streaming_enabled = streaming,
        ).toRALLMGenerateRequest(turn.prompt).copy(
            conversation_id = conversationId,
            history = turn.history,
        )

    private fun toProtoMessage(message: ChatMessage): ProtoChatMessage? {
        val content = message.text.takeIf(String::isNotBlank) ?: return null
        return ProtoChatMessage(
            role = if (message.isUser) {
                MessageRole.MESSAGE_ROLE_USER
            } else {
                MessageRole.MESSAGE_ROLE_ASSISTANT
            },
            content = content,
        )
    }
}
