package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ToolCallingResult
import ai.runanywhere.proto.v1.ToolResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChatToolResultNormalizerTest {
    @Test
    fun `commons-split text and thinking_content are presented as-is`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "The answer is 396.",
                thinking_content = "private calculation",
            ),
        )

        assertEquals("The answer is 396.", normalized.text)
        assertEquals("private calculation", normalized.thinking)
    }

    @Test
    fun `blank text falls back to a successful calculation payload`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "",
                thinking_content = "Thinking Process: calculate returned successfully",
                tool_results = listOf(
                    ToolResult(
                        name = "calculate",
                        result_json = """{"result":"396"}""",
                    ),
                ),
            ),
        )

        assertEquals("Result: 396", normalized.text)
        assertEquals("Thinking Process: calculate returned successfully", normalized.thinking)
    }

    @Test
    fun `blank text falls back to a sourced search_web payload`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "",
                thinking_content = "still reasoning",
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
    }

    @Test
    fun `typed thinking_content is authoritative when text is already answer-only`() {
        val normalized = ChatToolResultNormalizer.normalize(
            ToolCallingResult(
                text = "Visible answer.",
                thinking_content = "typed reasoning",
            ),
        )

        assertEquals("Visible answer.", normalized.text)
        assertEquals("typed reasoning", normalized.thinking)
    }

    @Test
    fun `blank everything surfaces the empty-answer message`() {
        val normalized = ChatToolResultNormalizer.normalize(ToolCallingResult(text = ""))

        assertEquals("The model did not produce a visible answer.", normalized.text)
        assertNull(normalized.thinking)
    }
}
