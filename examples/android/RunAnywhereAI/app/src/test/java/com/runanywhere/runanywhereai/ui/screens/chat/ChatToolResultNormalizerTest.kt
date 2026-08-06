package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ToolCallingResult
import ai.runanywhere.proto.v1.ToolResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatToolResultNormalizerTest {
    @Test
    fun `complete thinking block is split from the visible answer`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(text = "<think>private calculation</think>\nThe answer is 396."),
        )

        assertEquals("The answer is 396.", normalized.text)
        assertEquals("private calculation", normalized.thinking)
        assertNoThinkingTags(normalized)
    }

    @Test
    fun `malformed and mismatched tags never reach visible or thinking text`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "</think><think data-bad='1'>private plan</thinking>Visible answer.</think>",
            ),
        )

        assertEquals("Visible answer.", normalized.text)
        assertEquals("private plan", normalized.thinking)
        assertNoThinkingTags(normalized)
    }

    @Test
    fun `unclosed reasoning-only result falls back to successful calculation`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "<think>\nThinking Process: calculate returned successfully but the token cap ended here",
                tool_results = listOf(
                    ToolResult(
                        name = "calculate",
                        result_json = """{"result":"396"}""",
                    ),
                ),
            ),
        )

        assertEquals("Result: 396", normalized.text)
        assertTrue(normalized.thinking.orEmpty().startsWith("Thinking Process:"))
        assertNoThinkingTags(normalized)
    }

    @Test
    fun `unclosed reasoning-only text is recovered without displaying reasoning`() {
        // ToolCallingResult.raw_text was deleted outright; `text` is the sole
        // final-response field now, so this exercises the same unclosed-tag
        // recovery path through it directly.
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "<think>still reasoning",
                tool_results = listOf(
                    ToolResult(
                        name = "search_web",
                        result_json = """{"summary":"A concise sourced answer.","source_url":"https://example.com"}""",
                    ),
                ),
            ),
        )

        assertEquals("A concise sourced answer.\nSource: https://example.com", normalized.text)
        assertEquals("still reasoning", normalized.thinking)
        assertNoThinkingTags(normalized)
    }

    @Test
    fun `typed thinking is authoritative and sanitized`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "<think>raw reasoning</think>Visible answer.",
                thinking_content = "<thinking>typed reasoning</thinking>",
            ),
        )

        assertEquals("Visible answer.", normalized.text)
        assertEquals("typed reasoning", normalized.thinking)
        assertNoThinkingTags(normalized)
    }

    private fun assertNoThinkingTags(result: NormalizedChatToolResult) {
        val all = result.text + result.thinking.orEmpty()
        assertFalse(all.contains("<think", ignoreCase = true))
        assertFalse(all.contains("</think", ignoreCase = true))
    }
}
