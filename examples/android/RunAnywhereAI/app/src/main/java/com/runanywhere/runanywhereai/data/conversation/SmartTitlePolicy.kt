package com.runanywhere.runanywhereai.data.conversation

import com.runanywhere.sdk.public.types.RALLMGenerationOptions

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

    fun generationOptions(systemPrompt: String): RALLMGenerationOptions =
        RALLMGenerationOptions(
            max_tokens = MAX_TOKENS,
            temperature = TEMPERATURE,
            system_prompt = systemPrompt,
            disable_thinking = true,
        )

    fun normalizedTitle(raw: String): String? {
        var visible = raw
        // Strip complete blocks first, including the alternate tag pair used by commons.
        val complete = Regex(
            pattern = "<\\s*(?:think|thinking)\\b[^>]*>.*?<\\s*/\\s*(?:think|thinking)\\s*>",
            options = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        )
        visible = complete.replace(visible, "")

        // A token-capped title often ends inside an unclosed reasoning block.
        // Everything from that opening marker is reasoning-only, matching the
        // shared commons strip policy rather than saving it as a conversation title.
        val unclosedOpen = Regex(
            pattern = "<\\s*(?:think|thinking)\\b[^>]*(?:>|$)",
            options = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        ).find(visible)
        if (unclosedOpen != null) visible = visible.substring(0, unclosedOpen.range.first)

        visible = Regex("<\\s*/?\\s*(?:think|thinking)\\b[^>]*>?", RegexOption.IGNORE_CASE)
            .replace(visible, "")
        return visible
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
