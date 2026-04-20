// SPDX-License-Identifier: Apache-2.0
package com.runanywhere.sdk.`public`

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

class ChatSessionTest {
    @Test
    fun `renderMessages produces ChatML`() {
        val rendered = ChatSession.renderMessages(listOf(
            ChatMessage.system("You are helpful."),
            ChatMessage.user("Hi"),
        ), skipSystem = false)
        assertTrue(rendered.contains("<|im_start|>system"))
        assertTrue(rendered.contains("You are helpful."))
        assertTrue(rendered.contains("<|im_start|>user"))
        assertTrue(rendered.endsWith("<|im_start|>assistant\n"))
    }

    @Test
    fun `renderMessages skips system when requested`() {
        val rendered = ChatSession.renderMessages(listOf(
            ChatMessage.system("sys"),
            ChatMessage.user("hi"),
        ), skipSystem = true)
        assertFalse(rendered.contains("<|im_start|>system"))
        assertTrue(rendered.contains("<|im_start|>user"))
    }
}

class ToolFormatterTest {
    @Test
    fun `systemPrompt emits tool schema`() {
        val tools = listOf(ToolDefinition(
            name = "get_weather",
            description = "Get weather for a city",
            parameters = listOf(
                ToolParameter("city", "string", "City name"),
                ToolParameter("unit", "string", "C or F", required = false),
            )))
        val p = ToolFormatter.systemPrompt(tools)
        assertTrue(p.contains("get_weather"))
        assertTrue(p.contains("city"))
        assertTrue(p.contains("optional"))
        assertTrue(p.contains("<tool_call>"))
    }

    @Test
    fun `parseToolCalls extracts valid call`() {
        val raw = """Sure.
            <tool_call>{"name":"get_weather","arguments":{"city":"Paris"}}</tool_call>"""
        val calls = ToolFormatter.parseToolCalls(raw)
        assertEquals(1, calls.size)
        assertEquals("get_weather", calls[0].name)
        assertEquals("Paris", calls[0].arguments["city"])
    }

    @Test
    fun `parseToolCalls skips malformed`() {
        val raw = """<tool_call>not json</tool_call>
            <tool_call>{"name":"valid","arguments":{}}</tool_call>"""
        val calls = ToolFormatter.parseToolCalls(raw)
        assertEquals(1, calls.size)
        assertEquals("valid", calls[0].name)
    }
}

class StructuredOutputTest {
    @Test
    fun `extractJSON handles fenced block`() {
        val raw = """Sure:
            ```json
            {"name":"Alice"}
            ```
            """
        val json = StructuredOutput.extractJSON(raw)
        assertEquals("""{"name":"Alice"}""", json)
    }

    @Test
    fun `extractJSON handles bare object with surrounding prose`() {
        val raw = """Answer: {"result":42} ok?"""
        val json = StructuredOutput.extractJSON(raw)
        assertEquals("""{"result":42}""", json)
    }

    @Test
    fun `extractJSON handles nested braces`() {
        val raw = """{"outer":{"inner":true}}"""
        assertEquals(raw, StructuredOutput.extractJSON(raw))
    }

    @Test
    fun `extractJSON throws when no JSON`() {
        assertFailsWith<StructuredOutput.ParseFailedException> {
            StructuredOutput.extractJSON("no json at all")
        }
    }
}

class ModelFormatTest {
    @Test
    fun `ModelFormat raw values match C ABI`() {
        assertEquals(0, ModelFormat.UNKNOWN.raw)
        assertEquals(1, ModelFormat.GGUF.raw)
        assertEquals(2, ModelFormat.ONNX.raw)
        assertEquals(6, ModelFormat.WHISPERKIT.raw)
    }
}

class SDKStateEnvironmentTest {
    @Test
    fun `Environment raw values match C ABI`() {
        assertEquals(0, SDKState.Environment.DEVELOPMENT.raw)
        assertEquals(1, SDKState.Environment.STAGING.raw)
        assertEquals(2, SDKState.Environment.PRODUCTION.raw)
    }

    @Test
    fun `Environment of returns correct value`() {
        assertEquals(SDKState.Environment.DEVELOPMENT, SDKState.Environment.of(0))
        assertEquals(SDKState.Environment.STAGING, SDKState.Environment.of(1))
        assertEquals(SDKState.Environment.PRODUCTION, SDKState.Environment.of(99))
    }
}
