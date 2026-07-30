package com.runanywhere.runanywhereai.ui.screens.chat

import com.runanywhere.sdk.public.api.ChatRole
import com.runanywhere.sdk.public.api.ChatMessage as SdkChatMessage

internal data class ChatTurnSnapshot(
    val prompt: String,
    val history: List<SdkChatMessage>,
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
            history = messages.mapNotNull(::toSdkMessage),
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
        // The current prompt + system prompt already fill the input budget — drop history entirely.
        // Expected only for an extremely tight context or a very long single prompt.
        if (available <= 0) return turn.copy(history = emptyList())
        val kept = ArrayDeque<SdkChatMessage>()
        for (message in turn.history.asReversed()) { // keep the most RECENT turns that fit
            val cost = est(message.content)
            if (cost > available) break
            available -= cost
            kept.addFirst(message)
        }
        return if (kept.size == turn.history.size) turn else turn.copy(history = kept.toList())
    }

    /** The transcript handed to `llm.generate`: prior turns then the current prompt. */
    fun toMessages(turn: ChatTurnSnapshot): List<SdkChatMessage> =
        turn.history + SdkChatMessage(role = ChatRole.USER, content = turn.prompt)

    private fun toSdkMessage(message: ChatMessage): SdkChatMessage? {
        val content = message.text.takeIf(String::isNotBlank) ?: return null
        return SdkChatMessage(
            role = if (message.isUser) ChatRole.USER else ChatRole.ASSISTANT,
            content = content,
        )
    }
}
