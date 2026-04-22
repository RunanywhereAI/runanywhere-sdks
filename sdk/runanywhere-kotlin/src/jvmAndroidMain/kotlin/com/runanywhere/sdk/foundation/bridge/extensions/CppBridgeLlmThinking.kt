/*
 * CppBridgeLlmThinking.kt
 *
 * v3-readiness Phase A8 / GAP 08 #6. Kotlin facade over the
 * rac_llm_thinking C ABI (declared in
 * `rac/features/llm/rac_llm_thinking.h`, implemented in
 * `rac_llm_thinking.cpp`). Gives the Kotlin SDK byte-for-byte parity
 * with Swift's `CppBridge+LLMThinking.swift` for <think>-tag parsing
 * — critical for cross-SDK streaming UIs that render thinking vs
 * answer content differently.
 *
 * The thin-typed layer wraps the JNI shape
 * (`Array<String?>?`/`IntArray?`) into ordinary Kotlin data classes
 * + exceptions for clean call sites. All methods are pure / idempotent
 * / thread-safe (the C ABI uses a thread_local arena, so copying
 * strings through JNI as we do here is safe across threads).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/** Result of [CppBridgeLlmThinking.extract]: the response text plus
 *  the optional thinking chunk. */
data class LlmThinkingExtraction(
    val response: String,
    val thinking: String?,
)

/** Token-split result from [CppBridgeLlmThinking.splitTokens]. */
data class LlmThinkingTokenSplit(
    val thinkingTokens: Int,
    val responseTokens: Int,
)

/**
 * Pure utility around the `rac_llm_thinking` C ABI. Mirrors Swift's
 * `ThinkingContentParser`:
 *
 *   - [extract] — split on the FIRST `<think>...</think>` block.
 *     Inside-think → `thinking`; outside (before + after, joined by
 *     `\n`) → `response`. Empty/no-block input returns `thinking=null`
 *     and the full input as the response.
 *
 *   - [strip] — drop ALL `<think>...</think>` blocks plus any trailing
 *     unclosed `<think>`. Returns the trimmed remainder.
 *
 *   - [splitTokens] — apportion a total token count between thinking
 *     and response by character-length ratio. Used for accurate
 *     per-segment cost/usage accounting.
 */
object CppBridgeLlmThinking {
    /**
     * Extract the first think block.
     *
     * @throws IllegalStateException if the C ABI returns a null-pointer
     *   error (input was null on the C side — shouldn't happen since we
     *   always pass a non-null String here, but defensive).
     */
    fun extract(text: String): LlmThinkingExtraction {
        val arr = RunAnywhereBridge.racLlmExtractThinking(text)
            ?: throw IllegalStateException(
                "rac_llm_extract_thinking returned null; check logs")
        val response = arr[0] ?: ""   // never null on success per C ABI doc
        val thinking = arr.getOrNull(1)
        return LlmThinkingExtraction(response, thinking)
    }

    /**
     * Strip all think blocks from text.
     *
     * @throws IllegalStateException if the C ABI returns null (defensive).
     */
    fun strip(text: String): String {
        return RunAnywhereBridge.racLlmStripThinking(text)
            ?: throw IllegalStateException(
                "rac_llm_strip_thinking returned null; check logs")
    }

    /**
     * Split a total-tokens count between thinking + response segments
     * proportionally by character length.
     *
     * If `thinking` is null or empty: returns `(0, total)`.
     * Else: proportional split with `thinking + response == total`.
     */
    fun splitTokens(
        totalCompletionTokens: Int,
        response: String?,
        thinking: String?,
    ): LlmThinkingTokenSplit {
        val arr = RunAnywhereBridge.racLlmSplitThinkingTokens(
            totalCompletionTokens, response, thinking,
        ) ?: throw IllegalStateException(
            "rac_llm_split_thinking_tokens returned null; check logs")
        return LlmThinkingTokenSplit(
            thinkingTokens = arr[0],
            responseTokens = arr[1],
        )
    }
}
