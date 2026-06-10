package com.runanywhere.runanywhereai.data.conversation

import ai.runanywhere.proto.v1.ThinkingTagPattern
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import java.io.File

object ConversationRepository {
    const val DEFAULT_TITLE = "New chat"

    private var store: ConversationStore? = null

    var summaries by mutableStateOf<List<ConversationSummary>>(emptyList())
        private set

    // Full conversations kept in memory so search can match message text
    // (mirrors iOS ConversationStore.conversations).
    private var conversations by mutableStateOf<List<StoredConversation>>(emptyList())

    fun initialize(context: Context) {
        if (store == null) {
            store = ConversationStore(File(context.filesDir, "conversations"))
        }
    }

    suspend fun refresh() {
        conversations = store?.loadAll().orEmpty()
            .sortedWith(compareByDescending<StoredConversation> { it.pinned }.thenByDescending { it.updatedAt })
        summaries = conversations.map { it.toSummary() }
    }

    suspend fun get(id: String): StoredConversation? = store?.load(id)

    suspend fun save(conversation: StoredConversation) {
        store?.save(conversation)
        refresh()
    }

    suspend fun rename(id: String, title: String) {
        val existing = store?.load(id) ?: return
        store?.save(existing.copy(title = title.trim().ifBlank { existing.title }))
        refresh()
    }

    suspend fun setPinned(id: String, pinned: Boolean) {
        val existing = store?.load(id) ?: return
        store?.save(existing.copy(pinned = pinned))
        refresh()
    }

    suspend fun delete(id: String) {
        store?.delete(id)
        refresh()
    }

    // Mirrors iOS ConversationStore.searchConversations (title + message text,
    // case-insensitive) plus ConversationRow's matching-content preview.
    fun search(query: String): List<ConversationSummary> {
        if (query.isBlank()) return summaries
        return conversations.mapNotNull { conversation ->
            val titleMatches = conversation.title.contains(query, ignoreCase = true)
            val matchingMessage = if (titleMatches) {
                null
            } else {
                conversation.messages.firstOrNull { it.text.contains(query, ignoreCase = true) }
            }
            if (!titleMatches && matchingMessage == null) return@mapNotNull null
            conversation.toSummary().copy(matchPreview = matchingMessage?.let { matchPreview(it.text, query) })
        }
    }

    // Mirrors iOS ConversationStore.generateTitle: first line, capped at 50 chars.
    fun fallbackTitle(content: String): String =
        content.trim().lineSequence().firstOrNull().orEmpty().take(TITLE_MAX_LENGTH)

    /**
     * Mirrors iOS ConversationStore.generateSmartTitleIfNeeded: only runs while
     * the title is still the default or the deterministic fallback, builds the
     * prompt from the first four messages, and keeps the fallback on any failure.
     * iOS uses the Apple Foundation Models system LLM; Android uses the loaded
     * model through the same SDK generate entry point.
     */
    suspend fun generateSmartTitleIfNeeded(id: String) {
        val conversation = store?.load(id) ?: return
        val firstUserText = conversation.messages.firstOrNull { it.isUser }?.text
        val fallback = firstUserText?.let(::fallbackTitle) ?: DEFAULT_TITLE
        if (conversation.title != DEFAULT_TITLE && conversation.title != fallback) return

        val conversationText = conversation.messages
            .take(TITLE_CONTEXT_MESSAGES)
            .joinToString("\n") { message ->
                "${if (message.isUser) "User" else "Assistant"}: ${message.text.take(TITLE_CONTEXT_CHARS)}"
            }

        val title = runCatching {
            RunAnywhere.generate(
                prompt = "Create a descriptive, readable title for this conversation:\n\n$conversationText\n\nTitle:",
                options = RALLMGenerationOptions(
                    max_tokens = TITLE_MAX_TOKENS,
                    temperature = TITLE_TEMPERATURE,
                    system_prompt = TITLE_INSTRUCTIONS,
                    thinking_pattern = ThinkingTagPattern(open_tag = "<think>", close_tag = "</think>"),
                ),
            ).takeIf { it.error_message.isNullOrBlank() }?.text
        }.onFailure { RACLog.w("smart title generation failed: ${it.message}") }
            .getOrNull()
            ?.trim()
            ?.replace("\"", "")
            ?.take(TITLE_MAX_LENGTH)
        if (title.isNullOrBlank()) return

        // Re-load before writing so a reply persisted meanwhile is not clobbered.
        val current = store?.load(id) ?: return
        store?.save(current.copy(title = title))
        refresh()
    }

    private fun matchPreview(text: String, query: String): String {
        val index = text.indexOf(query, ignoreCase = true)
        if (index < 0) return text.take(100)
        val start = (index - MATCH_CONTEXT_CHARS).coerceAtLeast(0)
        val end = (index + query.length + MATCH_CONTEXT_CHARS).coerceAtMost(text.length)
        return buildString {
            if (start > 0) append("...")
            append(text.substring(start, end).replace("\n", " "))
            if (end < text.length) append("...")
        }
    }

    private const val TITLE_MAX_LENGTH = 50
    private const val TITLE_CONTEXT_MESSAGES = 4
    private const val TITLE_CONTEXT_CHARS = 200
    private const val TITLE_MAX_TOKENS = 32
    private const val TITLE_TEMPERATURE = 0.7f
    private const val MATCH_CONTEXT_CHARS = 30
    private val TITLE_INSTRUCTIONS = """
        You are an expert at creating descriptive, readable chat titles.
        Generate a clear title (2-5 words) that captures the main topic.
        Respond in the same language as the conversation.
        Only output the title, nothing else.
    """.trimIndent()
}

private fun StoredConversation.toSummary(): ConversationSummary {
    val lastText = messages.lastOrNull { it.text.isNotBlank() }?.text.orEmpty()
    return ConversationSummary(
        id = id,
        title = title,
        updatedAt = updatedAt,
        preview = lastText.replace("\n", " ").trim().take(90),
        pinned = pinned,
    )
}
