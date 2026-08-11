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

    /**
     * Formerly trimmed oldest turns with a local chars/token estimate. Commons
     * owns TokenUsage; there is no exported turn-windowing API, so do not invent
     * app-side token budgets — return history unchanged.
     */
    @Suppress("UNUSED_PARAMETER")
    fun windowHistory(
        turn: ChatTurnSnapshot,
        contextTokens: Int,
        outputTokens: Int,
        systemPrompt: String?,
    ): ChatTurnSnapshot = turn

    fun buildRequest(
        turn: ChatTurnSnapshot,
        options: RALLMGenerationOptions,
        conversationId: String,
        streaming: Boolean,
    ): RALLMGenerateRequest {
        // `LLMGenerateRequest.history` was deleted outright: the request now
        // carries only `messages` (oldest first, ending with the turn the
        // model must answer). Prepend the prior turns to the single-message
        // list `toRALLMGenerateRequest` built for the current prompt.
        val request = options.toRALLMGenerateRequest(turn.prompt)
        return request.copy(
            conversation_id = conversationId,
            messages = turn.history + request.messages,
        )
    }

    /**
     * Flatten prior turns into the commons tool-calling history contract: a flat
     * alternating [user0, asst0, user1, asst1, ...] string list of PRIOR turns.
     * The tool-calling proto carries history as plain strings (no roles) to avoid
     * a cross-proto import cycle, so — unlike the standard path, where commons
     * (llm_module.cpp) normalizes a role-tagged ChatMessage list — the app must
     * normalize here. Mirrors that normalizer exactly: drop non-user/assistant +
     * blank turns, drop a leading assistant, coalesce consecutive same-role turns
     * (join with a blank line), and drop a dangling trailing user. Without the
     * coalesce, a dropped blank assistant reply yields [user, user], which commons
     * would mislabel positionally (its odd-length guard only catches odd counts).
     */
    fun toToolCallingHistory(history: List<ProtoChatMessage>): List<String> {
        val turns = mutableListOf<String>()
        var lastRole: MessageRole? = null
        for (message in history) {
            val role = message.role
            if (role != MessageRole.MESSAGE_ROLE_USER &&
                role != MessageRole.MESSAGE_ROLE_ASSISTANT
            ) {
                continue
            }
            if (message.content.isEmpty()) continue
            if (turns.isEmpty() && role != MessageRole.MESSAGE_ROLE_USER) continue
            if (role == lastRole) {
                turns[turns.lastIndex] = turns[turns.lastIndex] + "\n\n" + message.content
            } else {
                turns.add(message.content)
                lastRole = role
            }
        }
        if (lastRole == MessageRole.MESSAGE_ROLE_USER && turns.isNotEmpty()) {
            turns.removeAt(turns.lastIndex)
        }
        return turns
    }

    private fun toProtoMessage(message: ChatMessage): ProtoChatMessage? {
        // A failed turn is the APP's report, not something the model said, so it must never
        // come back as a prior assistant message — otherwise the next request tells the model
        // it previously answered "Error: Backend not available for: llm" and it starts
        // apologising for a failure it had no part in. iOS skips the same turns when it builds
        // history (LLMViewModel+Generation), and the web `conversationHistoryForGeneration`
        // now filters on the same flag.
        if (message.isError) return null
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
