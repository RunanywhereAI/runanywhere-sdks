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
     * Trim the OLDEST prior turns so the prompt fits the model's context window. Small-context QHexRT
     * models (e.g. Llama-3.2-1B = 512 on v79) otherwise fail with rc=-130 (generation-failed) once the
     * accumulated conversation + the reply overrun MAXCTX. The output budget already reserves ~half the
     * context (ChatGenerationBudgetPolicy); the input side (system + kept history + current prompt +
     * template markers) must fit in the rest. There is no tokenizer on the app side, so token counts are
     * ESTIMATED and deliberately over-counted (≈3 chars/token + per-message role markers) plus a context
     * margin — better to trim a turn early than to overflow and crash. Large-context models (Qwen3.5 =
     * 1024) keep their full history for normal conversations; only long chats on tiny models get trimmed.
     */
    fun windowHistory(
        turn: ChatTurnSnapshot,
        contextTokens: Int,
        outputTokens: Int,
        systemPrompt: String?,
    ): ChatTurnSnapshot {
        if (contextTokens <= 0 || turn.history.isEmpty()) return turn // unknown context → don't trim
        fun est(text: String): Int = (text.length / 3) + 8 // ~3 chars/token over-estimate + role markers
        val margin = maxOf(24, contextTokens / 6) // BOS/system/generation-prompt markers + estimate slack
        val inputBudget = (contextTokens - outputTokens - margin).coerceAtLeast(16)
        val fixed = (systemPrompt?.takeIf { it.isNotBlank() }?.let { est(it) } ?: 0) + est(turn.prompt)
        var available = inputBudget - fixed
        if (available <= 0) return turn.copy(history = emptyList()) // no room for any history
        val kept = ArrayDeque<ProtoChatMessage>()
        for (message in turn.history.asReversed()) { // keep the most RECENT turns that fit
            val cost = est(message.content)
            if (cost > available) break
            available -= cost
            kept.addFirst(message)
        }
        return if (kept.size == turn.history.size) turn else turn.copy(history = kept.toList())
    }

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
