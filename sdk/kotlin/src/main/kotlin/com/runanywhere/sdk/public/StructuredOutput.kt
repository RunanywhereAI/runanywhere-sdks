// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

/**
 * Helpers for coaxing JSON out of LLM output. Pair with ChatSession to
 * decode into typed objects via your JSON library of choice.
 */
object StructuredOutput {

    class ParseFailedException(message: String) : Exception(message)

    /** Wraps `query` with a schema hint and a no-prose instruction. */
    fun renderQuery(query: String, schemaHint: String): String = """
        $query

        Respond with a JSON object matching this schema:
        $schemaHint

        Respond ONLY with valid JSON. No prose before or after. No markdown
        code fences. Just the JSON object.
    """.trimIndent()

    /** Extract first balanced top-level JSON object from arbitrary text. */
    fun extractJSON(text: String): String {
        // Try fenced ```json ... ``` first
        val fenced = Regex("```(?:json)?\\s*([\\s\\S]*?)```").find(text)?.groupValues?.get(1)?.trim()
        if (fenced != null && (fenced.startsWith("{") || fenced.startsWith("["))) {
            return fenced
        }
        val start = text.indexOf('{')
        if (start < 0) throw ParseFailedException("no '{' in: $text")
        var depth = 0
        var inString = false
        var escaped = false
        for (i in start until text.length) {
            val c = text[i]
            if (escaped) { escaped = false; continue }
            if (c == '\\') { escaped = true; continue }
            if (c == '"') { inString = !inString; continue }
            if (inString) continue
            if (c == '{') depth++
            else if (c == '}') {
                depth--
                if (depth == 0) return text.substring(start, i + 1)
            }
        }
        throw ParseFailedException("unbalanced braces in: $text")
    }
}
