/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kotlin port of Swift's `ThinkingContentParser`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift).
 *
 * The Swift surface delegates to the C ABI in
 * `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h`
 * (rac_llm_extract_thinking / rac_llm_strip_thinking /
 * rac_llm_split_thinking_tokens).
 *
 * No matching `racThinking*` / `racLlm*Thinking*` JNI thunks are exposed on
 * `RunAnywhereBridge` today, so this object reproduces the same `<think>...</think>`
 * splitting heuristic in pure Kotlin. Behavioral parity with Swift + commons:
 *   - Extract returns the FIRST `<think>...</think>` block; remainder is
 *     `before` + `\n` + `after` (each side trimmed, joined only when both
 *     non-empty).
 *   - Strip removes ALL complete blocks AND a trailing unclosed `<think>`
 *     (streaming case), then trims the result.
 *   - Token split uses character-length ratio on (thinking + response) and
 *     guarantees `thinking + response == total`.
 *
 * If the JNI thunks land later (commons CPP-02 follow-up), this implementation
 * can be swapped for `RunAnywhereBridge.racLlm*` calls without changing the
 * public surface.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Drop-in Kotlin equivalent of Swift's `ThinkingContentParser`.
 *
 * Provides the three operations every LLM frontend needs to render
 * `<think>...</think>` blocks consistently across SDKs.
 */
object CppBridgeLLMThinking {
    private const val OPEN_TAG = "<think>"
    private const val CLOSE_TAG = "</think>"

    /**
     * Result of [extract]: the trimmed response text plus the optional
     * thinking block (null when no well-formed `<think>...</think>` block
     * was present).
     */
    data class ExtractResult(
        val text: String,
        val thinking: String?,
    )

    /**
     * Result of [splitTokens]: tokens apportioned between thinking and response.
     */
    data class TokenSplit(
        val thinkingTokens: Int,
        val responseTokens: Int,
    )

    /**
     * Extract the FIRST `<think>...</think>` block from [text]. Returns the
     * trimmed remainder plus the inside-block content (or null if absent or
     * malformed).
     */
    fun extract(text: String): ExtractResult {
        val open = text.indexOf(OPEN_TAG)
        val close = text.indexOf(CLOSE_TAG)

        // No well-formed block: open missing, close missing, or close before
        // open's payload starts. Return original text untouched (parity with
        // C++ rac_llm_extract_thinking which preserves the raw text).
        if (open < 0 || close < 0 || open + OPEN_TAG.length > close) {
            return ExtractResult(text = text, thinking = null)
        }

        val thinking = text.substring(open + OPEN_TAG.length, close).trim()
        val before = text.substring(0, open).trim()
        val after = text.substring(close + CLOSE_TAG.length).trim()

        val response =
            when {
                before.isEmpty() && after.isEmpty() -> ""
                before.isEmpty() -> after
                after.isEmpty() -> before
                else -> "$before\n$after"
            }

        return ExtractResult(
            text = response,
            thinking = thinking.ifEmpty { null },
        )
    }

    /**
     * Strip ALL `<think>...</think>` blocks from [text] (including a trailing
     * unclosed `<think>` from in-flight streaming output). Returns the
     * trimmed remainder.
     */
    fun strip(text: String): String {
        val buf = StringBuilder(text)

        // Remove all complete <think>...</think> blocks.
        while (true) {
            val open = buf.indexOf(OPEN_TAG)
            if (open < 0) break
            val close = buf.indexOf(CLOSE_TAG, open + OPEN_TAG.length)
            if (close < 0) break
            buf.delete(open, close + CLOSE_TAG.length)
        }

        // Drop trailing unclosed <think>... (still streaming).
        val trailingOpen = buf.lastIndexOf(OPEN_TAG)
        if (trailingOpen >= 0) {
            val afterOpen = trailingOpen + OPEN_TAG.length
            if (buf.indexOf(CLOSE_TAG, afterOpen) < 0) {
                buf.setLength(trailingOpen)
            }
        }

        return buf.toString().trim()
    }

    /**
     * Apportion [totalCompletionTokens] between thinking + response by the
     * character-length ratio of [thinkingContent] vs [responseText].
     *
     * Mirrors the Swift / commons heuristic: if [thinkingContent] is null or
     * empty, all tokens belong to the response; otherwise the split is
     * proportional, clamped to `[0, total]`, and `thinking + response == total`.
     */
    fun splitTokens(
        totalCompletionTokens: Int,
        responseText: String,
        thinkingContent: String?,
    ): TokenSplit {
        if (thinkingContent.isNullOrEmpty()) {
            return TokenSplit(thinkingTokens = 0, responseTokens = totalCompletionTokens)
        }

        val thinkingChars = thinkingContent.length
        val responseChars = responseText.length
        val totalChars = thinkingChars + responseChars

        if (totalChars == 0 || totalCompletionTokens <= 0) {
            return TokenSplit(thinkingTokens = 0, responseTokens = totalCompletionTokens)
        }

        val ratio = thinkingChars.toDouble() / totalChars.toDouble()
        var thinkingTokens = (ratio * totalCompletionTokens.toDouble()).toInt()
        if (thinkingTokens < 0) thinkingTokens = 0
        if (thinkingTokens > totalCompletionTokens) thinkingTokens = totalCompletionTokens

        return TokenSplit(
            thinkingTokens = thinkingTokens,
            responseTokens = totalCompletionTokens - thinkingTokens,
        )
    }
}
