package com.runanywhere.runanywhereai.data.conversation

import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.ReasoningMode
import com.runanywhere.sdk.public.api.ReasoningOptions

internal object SmartTitlePolicy {
    const val TIMEOUT_MILLIS: Long = 8_000L
    const val CANCEL_WAIT_MILLIS: Long = 3_000L
    const val MAX_LENGTH: Int = 50
    private const val MAX_TOKENS: Int = 32
    private const val TEMPERATURE: Float = 0.7f

    fun canAttempt(conversation: StoredConversation): Boolean =
        !conversation.smartTitleAttempted && titleCanBeReplaced(conversation)

    fun titleCanBeReplaced(conversation: StoredConversation): Boolean {
        val fallback = conversation.messages.firstOrNull { it.isUser }
            ?.text
            ?.let(::fallbackTitle)
            ?: ConversationRepository.DEFAULT_TITLE
        return conversation.title == ConversationRepository.DEFAULT_TITLE || conversation.title == fallback
    }

    fun generationOptions(systemPrompt: String): LlmOptions =
        LlmOptions(
            maxOutputTokens = MAX_TOKENS,
            temperature = TEMPERATURE,
            systemPrompt = systemPrompt,
            reasoning = ReasoningOptions(mode = ReasoningMode.OFF),
        )

    fun normalizedTitle(raw: String): String? {
        // LLMGenerationResult.text is already reasoning-free from commons.
        return raw
            .trim()
            .trim('"', '\'', '`')
            .lineSequence()
            .firstOrNull()
            ?.trim()
            ?.take(MAX_LENGTH)
            ?.takeIf { it.isNotBlank() }
    }

    private fun fallbackTitle(content: String): String =
        content.trim().lineSequence().firstOrNull().orEmpty().take(MAX_LENGTH)
}

/** Process-level claim that closes save/schedule races; persisted state closes restart races. */
internal class SmartTitleLifecycle {
    private val attemptedConversationIds = mutableSetOf<String>()
    private var activeConversationId: String? = null

    @Synchronized
    fun tryStart(conversationId: String): Boolean {
        if (conversationId.isBlank() || conversationId in attemptedConversationIds) return false
        if (activeConversationId != null) return false
        attemptedConversationIds += conversationId
        activeConversationId = conversationId
        return true
    }

    @Synchronized
    fun finish(conversationId: String) {
        if (activeConversationId == conversationId) activeConversationId = null
    }

    @Synchronized
    fun hasAttempted(conversationId: String): Boolean = conversationId in attemptedConversationIds
}
