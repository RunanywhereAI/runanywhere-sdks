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

    // LFM2 `<|tool_call_start|>…<|tool_call_end|>` and the DEFAULT `<tool_call>…</tool_call>` form.
    private val strayToolCall = Regex(
        """<\|tool_call_start\|>(.*?)<\|tool_call_end\|>|<tool_call>(.*?)</tool_call>""",
        RegexOption.DOT_MATCHES_ALL,
    )
    private val firstStringLiteral = Regex("\"([^\"]+)\"")

    fun normalize(result: ToolCallingResult): NormalizedChatToolResult {
        // Commons owns the reasoning/content split: ToolCallingResult.text is
        // answer-only and thinking_content is already de-tagged.
        val thinking = result.thinking_content?.takeIf { it.isNotBlank() }
        val text = result.text.trim().ifBlank {
            successfulToolFallback(result.tool_results)
                ?: result.error_message
                    ?.takeIf { it.isNotBlank() }
                    ?.let { "Error: ${it.trim()}" }
                ?: "The model did not produce a visible answer."
        }
        return NormalizedChatToolResult(
            text = text.ifBlank { "The model did not produce a visible answer." },
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
            // Group 1 carries the LFM2 form's body, group 2 the `<tool_call>` form's, and
            // only one alternative matches per hit, so read whichever is populated.
            val body = match.groupValues[1].ifEmpty { match.groupValues[2] }
            if (salvaged == null) salvaged = firstStringLiteral.find(body)?.groupValues?.get(1)
            ""
        }
        val remaining = withoutCalls.trim()
        return if (remaining.isNotEmpty()) remaining else salvaged?.trim().orEmpty()
    }

    private fun successfulToolFallback(results: List<ToolResult>): String? =
        results.asReversed().firstNotNullOfOrNull { result ->
            // Wire polarity: `success` -> `is_error` (inverted).
            val succeeded = result.result_json.isNotBlank() &&
                (!result.is_error || result.error.isNullOrBlank())
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
}
