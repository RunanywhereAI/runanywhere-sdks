package com.runanywhere.runanywhereai.util

/**
 * Pure-Kotlin helper for parsing `<think>...</think>` blocks out of raw model
 * output text. Mirrors the iOS `ThinkingContentParser` (in
 * `examples/ios/.../Utilities/ThinkingContentParser.swift`) byte-for-byte so
 * the cross-platform chat / RAG / tool-call UIs render thinking blocks the
 * same way on every platform.
 *
 * Used by callers that work on raw strings rather than the proto-backed
 * `RALLMGenerationResult` (which already exposes `thinkingContent` / `text`
 * separately):
 *
 *   - Streaming token accumulation: tokens are appended to a buffer for
 *     live UI preview; the SDK's terminal `RALLMGenerationResult` is
 *     consumed for the final analytics-aware update.
 *   - Tool calling: `RAToolCallingResult.text` carries raw text with
 *     `<think>` tags inline; the proto has no thinking_content field.
 *   - RAG: `RARAGResult.answer` likewise carries raw text with `<think>`
 *     tags embedded; the proto has no thinking_content field.
 *
 * The behaviour matches the commons-internal `rac_llm_extract_thinking` /
 * `rac_llm_strip_thinking` helpers (see
 * `sdk/runanywhere-commons/.../rac_llm_thinking.h`). Those C-ABI symbols
 * are NOT exposed from the Kotlin SDK by design — the proto already
 * carries the split for the canonical `RALLMGenerationResult` path; this
 * example-side helper covers the raw-string callsites.
 */
object ThinkingContentParser {
    /** Open tag exposed so call sites can do streaming flow-control without repeating the literal. */
    const val OPEN_TAG: String = "<think>"

    /** Close tag exposed so call sites can do streaming flow-control without repeating the literal. */
    const val CLOSE_TAG: String = "</think>"

    data class Extraction(
        /** Text with the first <think> block removed, trimmed. */
        val text: String,
        /** Contents of the first <think> block, trimmed. `null` when absent or empty. */
        val thinking: String?,
    )

    /**
     * Extract the FIRST `<think>...</think>` block from [raw]. Returns the
     * trimmed remainder (before + after, joined by `\n` when both sides
     * have content) plus the inside-block content (or null when no full
     * block is present).
     */
    fun extract(raw: String): Extraction {
        val openIdx = raw.indexOf(OPEN_TAG)
        val closeIdx = raw.indexOf(CLOSE_TAG)
        if (openIdx < 0 || closeIdx < 0 || openIdx + OPEN_TAG.length > closeIdx) {
            return Extraction(text = raw, thinking = null)
        }

        val thinking = raw.substring(openIdx + OPEN_TAG.length, closeIdx).trim()
        val before = raw.substring(0, openIdx).trim()
        val after = raw.substring(closeIdx + CLOSE_TAG.length).trim()

        val response =
            buildString {
                if (before.isNotEmpty()) append(before)
                if (after.isNotEmpty()) {
                    if (isNotEmpty()) append('\n')
                    append(after)
                }
            }

        return Extraction(text = response, thinking = thinking.ifEmpty { null })
    }

    /**
     * Strip ALL `<think>...</think>` blocks (including multiple blocks and
     * a trailing unclosed `<think>` left over from a still-streaming
     * response). Returns the trimmed remainder.
     */
    fun strip(raw: String): String {
        var buffer = raw

        // Remove every complete <think>...</think> block.
        while (true) {
            val openIdx = buffer.indexOf(OPEN_TAG)
            if (openIdx < 0) break
            val closeIdx = buffer.indexOf(CLOSE_TAG, startIndex = openIdx + OPEN_TAG.length)
            if (closeIdx < 0) break
            buffer = buffer.removeRange(openIdx, closeIdx + CLOSE_TAG.length)
        }

        // Drop a trailing unclosed <think>... (still streaming).
        val trailingOpen = buffer.lastIndexOf(OPEN_TAG)
        if (trailingOpen >= 0 && buffer.indexOf(CLOSE_TAG, startIndex = trailingOpen) < 0) {
            buffer = buffer.removeRange(trailingOpen, buffer.length)
        }

        return buffer.trim()
    }
}
