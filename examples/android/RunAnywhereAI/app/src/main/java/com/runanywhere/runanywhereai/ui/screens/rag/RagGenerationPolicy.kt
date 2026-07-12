package com.runanywhere.runanywhereai.ui.screens.rag

import ai.runanywhere.proto.v1.RAGQueryOptions
import com.runanywhere.sdk.public.extensions.defaults

internal object RagGenerationPolicy {
    const val MAX_OUTPUT_TOKENS = 192
    const val QUERY_TIMEOUT_MS = 30_000L

    private const val SYSTEM_PROMPT =
        "Answer using only the provided document context. " +
            "Give the direct answer in at most three concise sentences and 80 words. " +
            "Do not reveal reasoning, analysis, or thinking. " +
            "If the context is insufficient, say that clearly."

    fun options(question: String, multiQueryEnabled: Boolean): RAGQueryOptions =
        RAGQueryOptions.defaults(question = question).copy(
            system_prompt = SYSTEM_PROMPT,
            max_tokens = MAX_OUTPUT_TOKENS,
            temperature = 0.0f,
            top_p = 1.0f,
            top_k = 0,
            stream = false,
            disable_thinking = true,
            enable_multi_query = multiQueryEnabled,
        )
}

/** Identifies the query and corpus state that a native answer belongs to. */
internal data class RagQueryVersion(
    val query: Long,
    val corpus: Long,
) {
    fun isCurrent(currentQuery: Long, currentCorpus: Long): Boolean =
        query == currentQuery && corpus == currentCorpus
}

/** Final UI defense for complete, malformed, or token-truncated thinking tags. */
internal object RagAnswerNormalizer {
    private val thinkingTag = Regex(
        pattern = "<\\s*(/?)\\s*(?:think|thinking)\\b[^>]*>",
        option = RegexOption.IGNORE_CASE,
    )
    private val incompleteThinkingTag = Regex(
        pattern = "<\\s*/?\\s*(?:think|thinking)\\b[^>]*$",
        options = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )

    fun visibleAnswer(raw: String): String {
        if (raw.isBlank()) return ""
        val visible = mutableListOf<String>()
        var cursor = 0
        var insideThinking = false
        thinkingTag.findAll(raw).forEach { match ->
            if (!insideThinking) {
                raw.substring(cursor, match.range.first)
                    .trim()
                    .takeIf(String::isNotEmpty)
                    ?.let(visible::add)
            }
            insideThinking = match.groupValues[1].isEmpty()
            cursor = match.range.last + 1
        }
        if (!insideThinking) raw.substring(cursor).trim().takeIf(String::isNotEmpty)?.let(visible::add)

        val joined = visible.joinToString("\n")
        val incomplete = incompleteThinkingTag.find(joined)
        return if (incomplete != null && !incomplete.value.trimStart().startsWith("</")) {
            joined.substring(0, incomplete.range.first).trim()
        } else {
            incompleteThinkingTag.replace(joined, "").trim()
        }
    }
}
