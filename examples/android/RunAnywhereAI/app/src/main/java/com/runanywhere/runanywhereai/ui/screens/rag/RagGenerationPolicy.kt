package com.runanywhere.runanywhereai.ui.screens.rag

import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.ReasoningMode
import com.runanywhere.sdk.public.api.ReasoningOptions

internal object RagGenerationPolicy {
    const val MAX_OUTPUT_TOKENS = 192
    const val QUERY_TIMEOUT_MS = 30_000L

    private const val SYSTEM_PROMPT =
        "Answer using only the provided document context. " +
            "Give the direct answer in at most three concise sentences and 80 words. " +
            "Do not reveal reasoning, analysis, or thinking. " +
            "If the context is insufficient, say that clearly."

    fun options(): LlmOptions =
        LlmOptions(
            systemPrompt = SYSTEM_PROMPT,
            maxOutputTokens = MAX_OUTPUT_TOKENS,
            temperature = 0.0f,
            topP = 1.0f,
            reasoning = ReasoningOptions(mode = ReasoningMode.OFF),
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
