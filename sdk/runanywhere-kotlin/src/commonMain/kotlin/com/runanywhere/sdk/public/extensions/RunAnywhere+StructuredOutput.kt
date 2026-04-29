/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation.
 * Mirrors Swift RunAnywhere+StructuredOutput.swift.
 *
 * Round 2 KOTLIN: Renamed generateWithStructuredOutput → generateStructured,
 * added generateStructuredStream, extractThinkingTokens, stripThinkingTokens,
 * splitThinkingAndResponse.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.StructuredOutputResult
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// MARK: - Structured Output

/**
 * Generate structured output (JSON conforming to a schema) from a prompt.
 *
 * Canonical cross-SDK name. Replaces the deleted `generateWithStructuredOutput`.
 *
 * @param prompt The prompt to generate from
 * @param schema JSON schema that the output must conform to
 * @param options Optional generation options
 * @return [StructuredOutputResult] with the extracted JSON and validation info
 */
expect suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions? = null,
): StructuredOutputResult

/**
 * Stream structured output results for a prompt.
 *
 * @param prompt The prompt to generate from
 * @param schema JSON schema that the output must conform to
 * @param options Optional generation options
 * @return Flow of [StructuredOutputResult] chunks
 */
expect fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions? = null,
): Flow<StructuredOutputResult>

/**
 * Extract a JSON object from text. The C++ commons exposes this via
 * `rac_structured_output_extract_json` so the Kotlin SDK delegates.
 *
 * @param text The text containing JSON to extract
 * @param schemaJson Optional JSON Schema string used to validate the result
 * @return The extracted JSON string, or `null` if no valid JSON was found
 */
expect suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schemaJson: String? = null,
): StructuredOutputResult?

// MARK: - Thinking Token Helpers (pure Kotlin, no JNI needed)

/**
 * Result of extracting thinking tokens from LLM output.
 *
 * @param thinkingTokens The content inside all &lt;think&gt;...&lt;/think&gt; blocks, joined by newlines
 * @param response The remainder of the text with all think blocks removed
 */
data class ThinkingExtractionResult(
    val thinkingTokens: String,
    val response: String,
)

/**
 * Result of splitting the first thinking block from the response.
 *
 * @param thinking The content of the first &lt;think&gt;...&lt;/think&gt; block, or empty string
 * @param response The remainder of the text after the first think block
 */
data class ThinkingAndResponseSplit(
    val thinking: String,
    val response: String,
)

// Internal regex for parsing think tags — compiled once.
private val thinkTagRegex = Regex("<think>(.*?)</think>", setOf(RegexOption.DOT_MATCHES_ALL))

/**
 * Extract all thinking tokens from LLM output.
 *
 * Parses all `<think>...</think>` blocks, joins their contents with newlines,
 * and returns the remainder as [ThinkingExtractionResult.response].
 *
 * Pure Kotlin — no JNI needed.
 *
 * @param text Raw LLM output potentially containing think blocks
 * @return [ThinkingExtractionResult] with separated thinking and response content
 */
fun RunAnywhere.extractThinkingTokens(text: String): ThinkingExtractionResult {
    val thinking =
        thinkTagRegex
            .findAll(text)
            .map { it.groupValues[1].trim() }
            .joinToString("\n")
    val response = thinkTagRegex.replace(text, "").trim()
    return ThinkingExtractionResult(thinkingTokens = thinking, response = response)
}

/**
 * Strip all thinking tokens from LLM output.
 *
 * Removes all `<think>...</think>` blocks (including unclosed trailing ones)
 * and returns the trimmed remainder.
 *
 * Pure Kotlin — no JNI needed.
 *
 * @param text Raw LLM output potentially containing think blocks
 * @return Text with all think blocks removed
 */
fun RunAnywhere.stripThinkingTokens(text: String): String {
    // Remove complete blocks, then remove any unclosed trailing <think>
    val withoutBlocks = thinkTagRegex.replace(text, "")
    val withoutOpenTag = withoutBlocks.replace(Regex("<think>.*", setOf(RegexOption.DOT_MATCHES_ALL)), "")
    return withoutOpenTag.trim()
}

/**
 * Split the first thinking block from the response text.
 *
 * Extracts the first `<think>...</think>` block's content as [ThinkingAndResponseSplit.thinking],
 * and the remainder as [ThinkingAndResponseSplit.response].
 *
 * Pure Kotlin — no JNI needed.
 *
 * @param text Raw LLM output potentially containing a think block
 * @return [ThinkingAndResponseSplit] with the separated thinking and response
 */
fun RunAnywhere.splitThinkingAndResponse(text: String): ThinkingAndResponseSplit {
    val match = thinkTagRegex.find(text)
    return if (match != null) {
        val thinking = match.groupValues[1].trim()
        val response =
            (text.substring(0, match.range.first) + text.substring(match.range.last + 1))
                .trim()
        ThinkingAndResponseSplit(thinking = thinking, response = response)
    } else {
        ThinkingAndResponseSplit(thinking = "", response = text.trim())
    }
}
