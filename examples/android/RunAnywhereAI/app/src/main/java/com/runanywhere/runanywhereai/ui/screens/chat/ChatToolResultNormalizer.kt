package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ToolCallingResult
import ai.runanywhere.proto.v1.ToolResult
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

internal data class NormalizedChatToolResult(
    val text: String,
    val thinking: String?,
)

/** Final presentation guard for model output returned by the native tool loop. */
internal object ChatToolResultNormalizer {
    private val json = Json { ignoreUnknownKeys = true }

    // Matches the two tag pairs recognized by commons' thinking policy. Accepting
    // mismatched close names and malformed attributes keeps raw model markup out of UI.
    private val thinkingTag = Regex(
        pattern = "<\\s*(/?)\\s*(?:think|thinking)\\b[^>]*>",
        option = RegexOption.IGNORE_CASE,
    )
    // Also catches a stream stopped mid-tag ("answer <thi"): a trailing `<`, an
    // optional `/`, then any strict prefix of think/thinking with no closing `>`.
    // The full-word alternation keeps the prior behavior of trimming an unclosed
    // `<think ...` that carries attributes. A lone trailing `<` stays untouched so
    // a legitimate less-than at the end of an answer is preserved.
    // LFM2 `<|tool_call_start|>…<|tool_call_end|>` and the DEFAULT `<tool_call>…</tool_call>` form.
    private val strayToolCall = Regex(
        """<\|tool_call_start\|>(.*?)<\|tool_call_end\|>|<tool_call>(.*?)</tool_call>""",
        RegexOption.DOT_MATCHES_ALL,
    )
    private val firstStringLiteral = Regex("\"([^\"]+)\"")

    private val incompleteThinkingTag = Regex(
        pattern = "<\\s*/?\\s*(?:(?:think|thinking)\\b[^>]*|t(?:h(?:i(?:n(?:k(?:i(?:n(?:g)?)?)?)?)?)?)?)$",
        options = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )

    fun normalize(result: ToolCallingResult): NormalizedChatToolResult {
        val rawText = result.text.ifBlank {
            result.raw_text.takeIf { containsThinkingMarkup(it) }.orEmpty()
        }
        val split = splitThinking(rawText)
        val typedThinking = result.thinking_content
            ?.let(::sanitizeTypedThinking)
            ?.takeIf { it.isNotBlank() }
        val thinking = typedThinking ?: split.thinking.takeIf { it.isNotBlank() }

        val text = split.visibleText.ifBlank {
            successfulToolFallback(result.tool_results)
                ?: result.error_message
                    ?.takeIf { it.isNotBlank() }
                    ?.let { "Error: ${visibleOnly(it)}" }
                ?: "The model did not produce a visible answer."
        }
        return NormalizedChatToolResult(
            text = visibleOnly(text).ifBlank { "The model did not produce a visible answer." },
            thinking = thinking,
        )
    }

    /**
     * Strip stray tool-call markup from a reply produced on the STANDARD (no-tools) route.
     *
     * Tool-trained models emit their call syntax unprompted even when no tools are registered — LFM2.5
     * answers a plain "Hi my name is Aman" with
     * `<|tool_call_start|>[ask_user("What would you like to do today, Aman?")]<|tool_call_end|>`.
     * Commons parses that into LLMStreamEvent.tool_call regardless of whether tools were requested, but the
     * raw text still carries the markers, so on the standard route the user sees the literal tags.
     *
     * The call's first string literal is the model's intended user-facing sentence (that is the whole point
     * of an ask_user-style call), so surface it when the block is all there is; otherwise just remove the
     * block and keep the surrounding prose.
     */
    fun stripStrayToolCall(raw: String): String {
        if (raw.isBlank() || !strayToolCall.containsMatchIn(raw)) return raw
        var salvaged: String? = null
        val withoutCalls = strayToolCall.replace(raw) { match ->
            if (salvaged == null) salvaged = firstStringLiteral.find(match.groupValues[1])?.groupValues?.get(1)
            ""
        }
        val remaining = withoutCalls.trim()
        return if (remaining.isNotEmpty()) remaining else salvaged?.trim().orEmpty()
    }

    internal fun splitThinking(raw: String): ThinkingSplit {
        if (raw.isBlank()) return ThinkingSplit("", "")

        val visibleChunks = mutableListOf<String>()
        val thinkingChunks = mutableListOf<String>()
        var cursor = 0
        var insideThinking = false
        thinkingTag.findAll(raw).forEach { match ->
            addChunk(
                value = raw.substring(cursor, match.range.first),
                thinking = insideThinking,
                visibleChunks = visibleChunks,
                thinkingChunks = thinkingChunks,
            )
            insideThinking = match.groupValues[1].isEmpty()
            cursor = match.range.last + 1
        }
        addChunk(
            value = raw.substring(cursor),
            thinking = insideThinking,
            visibleChunks = visibleChunks,
            thinkingChunks = thinkingChunks,
        )

        // Commons' strip policy drops a trailing unclosed opening tag. Do the
        // same even when the model emitted an incomplete marker without `>`.
        val visible = visibleChunks.joinToString("\n")
        val incompleteOpen = incompleteThinkingTag.find(visible)
        val safeVisible = if (incompleteOpen != null && !incompleteOpen.value.trimStart().startsWith("</")) {
            visible.substring(0, incompleteOpen.range.first)
        } else {
            incompleteThinkingTag.replace(visible, "")
        }
        return ThinkingSplit(
            visibleText = safeVisible.trim(),
            thinking = thinkingChunks.joinToString("\n").let(::removeThinkingMarkup).trim(),
        )
    }

    private fun addChunk(
        value: String,
        thinking: Boolean,
        visibleChunks: MutableList<String>,
        thinkingChunks: MutableList<String>,
    ) {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return
        if (thinking) thinkingChunks += trimmed else visibleChunks += trimmed
    }

    private fun sanitizeTypedThinking(value: String): String {
        val split = splitThinking(value)
        return listOf(split.thinking, split.visibleText)
            .filter { it.isNotBlank() }
            .joinToString("\n")
            .let(::removeThinkingMarkup)
            .trim()
    }

    private fun successfulToolFallback(results: List<ToolResult>): String? =
        results.asReversed().firstNotNullOfOrNull { result ->
            val succeeded = result.result_json.isNotBlank() &&
                (result.success || result.error.isNullOrBlank())
            if (succeeded) summarizeToolResult(result) else null
        }

    private fun summarizeToolResult(result: ToolResult): String? {
        val root = runCatching { json.parseToJsonElement(result.result_json) }.getOrNull()
        val obj = root as? JsonObject
        val summary = when (result.name) {
            "calculate" -> obj.stringValue("result")?.let { "Result: $it" }
            "search_web" -> obj.stringValue("summary")?.let { text ->
                val source = obj.stringValue("source_url")
                if (source.isNullOrBlank()) text else "$text\nSource: $source"
            }
            "get_current_time" -> obj.stringValue("datetime")
            "get_battery_level" -> obj.stringValue("battery_percent")?.let { "Battery level: $it" }
            else -> obj.firstUsefulValue()
                ?: root?.firstPrimitiveValue()
                ?: result.result_json.takeIf { it.isNotBlank() }
        }
        return summary
            ?.let(::visibleOnly)
            ?.replace(Regex("[\\t ]+"), " ")
            ?.trim()
            ?.take(500)
            ?.takeIf { it.isNotBlank() }
            ?: result.name.takeIf { it.isNotBlank() }?.let { "${it.replace('_', ' ')} completed successfully." }
    }

    private fun JsonObject?.stringValue(key: String): String? =
        this?.get(key)?.firstPrimitiveValue()?.takeIf { it.isNotBlank() }

    private fun JsonObject?.firstUsefulValue(): String? {
        if (this == null) return null
        val preferred = listOf("answer", "result", "summary", "message", "datetime", "value")
        preferred.forEach { key -> stringValue(key)?.let { return it } }
        return values.firstNotNullOfOrNull { it.firstPrimitiveValue() }
    }

    private fun JsonElement.firstPrimitiveValue(): String? = when (this) {
        is JsonPrimitive -> contentOrNull
        is JsonObject -> firstUsefulValue()
        is JsonArray -> firstNotNullOfOrNull { it.firstPrimitiveValue() }
    }

    private fun visibleOnly(value: String): String = splitThinking(value).visibleText

    private fun containsThinkingMarkup(value: String): Boolean =
        thinkingTag.containsMatchIn(value) || incompleteThinkingTag.containsMatchIn(value)

    private fun removeThinkingMarkup(value: String): String =
        incompleteThinkingTag.replace(thinkingTag.replace(value, ""), "")

    internal data class ThinkingSplit(
        val visibleText: String,
        val thinking: String,
    )
}
