package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.ToolCall
import ai.runanywhere.proto.v1.ToolCallFormatName
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolCallingResult
import ai.runanywhere.proto.v1.ToolChoiceMode
import ai.runanywhere.proto.v1.ToolDefinition
import ai.runanywhere.proto.v1.ToolResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ToolCallingProtoAdaptersTest {
    @Test
    fun `top-level LLM options become generated tool options when no nested contract exists`() {
        val options =
            LLMGenerationOptions(
                max_tokens = 128,
                temperature = 0.4f,
                system_prompt = "Use tools when useful.",
            ).toToolCallingOptions()

        assertEquals(DEFAULT_TOOL_CALL_MAX_ITERATIONS, options.max_iterations)
        assertTrue(options.auto_execute)
        assertEquals(128, options.max_tokens)
        assertEquals(0.4f, options.temperature)
        assertEquals("Use tools when useful.", options.system_prompt)
        assertEquals("default", options.format_hint)
    }

    @Test
    fun `nested generated tool contract wins over top-level generation defaults`() {
        val options =
            LLMGenerationOptions(
                max_tokens = 128,
                temperature = 0.4f,
                tool_calling =
                    ToolCallingOptions(
                        max_tool_calls = 2,
                        auto_execute = false,
                        max_tokens = 64,
                        temperature = 0.1f,
                        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS,
                    ),
            ).toToolCallingOptions()

        assertEquals(2, options.max_iterations)
        assertFalse(options.auto_execute)
        assertEquals(64, options.max_tokens)
        assertEquals(0.1f, options.temperature)
        assertEquals("default", options.format_hint)
    }

    @Test
    fun `run loop request preserves greedy forced tool policy across Kotlin bridge`() {
        val search = ToolDefinition(name = "search_web", description = "Search current information")
        val request =
            makeToolCallingRunLoopRequest(
                prompt = "Use search_web for the current requirement.",
                options =
                    ToolCallingOptions(
                        tools = listOf(search),
                        max_iterations = 2,
                        max_tokens = 96,
                        temperature = 0f,
                        disable_thinking = true,
                        tool_choice = ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC,
                        forced_tool_name = "search_web",
                    ),
                llmOptions =
                    LLMGenerationOptions(
                        max_tokens = 512,
                        temperature = 0.7f,
                        top_p = 1f,
                        disable_thinking = false,
                    ),
                tools = listOf(search),
                validateCalls = null,
            )

        assertEquals(96, request.max_tokens)
        assertEquals(0f, request.temperature)
        assertEquals(1f, request.top_p)
        assertTrue(request.disable_thinking)
        assertEquals(ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC, request.tool_choice)
        assertEquals("search_web", request.forced_tool_name)
        assertEquals(listOf("search_web"), request.tools.map { it.name })
        assertEquals(null, request.validate_calls)
    }

    @Test
    fun `tool calling result maps into canonical LLM result fields`() {
        val call = ToolCall(id = "call_1", name = "get_weather", arguments_json = """{"city":"Paris"}""")
        val result = ToolResult(tool_call_id = "call_1", name = "get_weather", result_json = """{"temp":18}""")

        val llmResult =
            ToolCallingResult(
                text = "It is 18 C.",
                tool_calls = listOf(call),
                tool_results = listOf(result),
                is_complete = false,
            ).toLLMGenerationResult(modelUsed = "demo-model")

        assertEquals("It is 18 C.", llmResult.text)
        assertEquals("demo-model", llmResult.model_used)
        assertEquals("tool_calls", llmResult.finish_reason)
        assertEquals(listOf(call), llmResult.tool_calls)
        assertEquals(listOf(result), llmResult.tool_results)
    }

    @Test
    fun `tool executor consumes and returns RAToolValue map`() {
        val executor: ToolExecutor = { args ->
            val input = args["value"]?.string
            mapOf(
                "echo" to RAToolValue.string(input ?: ""),
                "ok" to RAToolValue.bool(true),
            )
        }

        kotlinx.coroutines.test.runTest {
            val result =
                executor(
                    mapOf("value" to RAToolValue.string("hello")),
                )

            assertEquals("hello", result["echo"]?.string)
            assertEquals(true, result["ok"]?.bool)
        }
    }
}
