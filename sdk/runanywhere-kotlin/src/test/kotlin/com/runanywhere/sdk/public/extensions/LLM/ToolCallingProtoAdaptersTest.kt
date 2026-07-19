package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.ToolCallFormatName
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolChoiceMode
import ai.runanywhere.proto.v1.ToolDefinition
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

        assertEquals(DEFAULT_MAX_TOOL_CALLS, options.max_tool_calls)
        assertTrue(options.auto_execute)
        assertEquals(128, options.max_tokens)
        assertEquals(0.4f, options.temperature)
        assertEquals("Use tools when useful.", options.system_prompt)
        assertEquals(null, options.format)
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
                        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2,
                    ),
            ).toToolCallingOptions()

        assertEquals(2, options.max_tool_calls)
        assertFalse(options.auto_execute)
        assertEquals(64, options.max_tokens)
        assertEquals(0.1f, options.temperature)
        assertEquals(ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2, options.format)
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
                        max_tool_calls = 2,
                        max_tokens = 96,
                        temperature = 0f,
                        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2,
                        auto_execute = false,
                        replace_system_prompt = true,
                        require_json_arguments = true,
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
        assertEquals(2, request.max_tool_calls)
        assertEquals(ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2, request.format)
        assertEquals(false, request.auto_execute)
        assertTrue(request.replace_system_prompt)
        assertTrue(request.require_json_arguments)
        assertTrue(request.disable_thinking)
        assertEquals(ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC, request.tool_choice)
        assertEquals("search_web", request.forced_tool_name)
        assertEquals(listOf("search_web"), request.tools.map { it.name })
        assertEquals(null, request.validate_calls)
    }

    @Test
    fun `run loop request carries multi-turn history onto the request`() {
        val priorTurns = listOf("What is the weather in Paris?", "It is 18C and sunny in Paris.")
        val request =
            makeToolCallingRunLoopRequest(
                prompt = "and in London?",
                options = ToolCallingOptions(tools = emptyList()),
                llmOptions = LLMGenerationOptions(max_tokens = 128),
                tools = emptyList(),
                validateCalls = null,
                history = priorTurns,
            )

        // History is threaded verbatim onto ToolCallingSessionCreateRequest.history
        // (proto field 19); the current turn stays in `prompt`, not history.
        assertEquals(priorTurns, request.history)
        assertEquals("and in London?", request.prompt)
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
