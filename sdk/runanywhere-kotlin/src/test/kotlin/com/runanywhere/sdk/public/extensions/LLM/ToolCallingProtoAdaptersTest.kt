package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.ToolCallFormatName
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolChoiceMode
import ai.runanywhere.proto.v1.ToolDefinition
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

class ToolCallingProtoAdaptersTest {
    @Test
    fun `absent nested tool contract falls back to generated defaults`() {
        val options = LLMGenerationOptions(temperature = 0.4f).toToolCallingOptions()

        assertEquals(ToolCallingOptions().max_tool_calls, options.max_tool_calls)
        assertEquals(null, options.format)
    }

    @Test
    fun `nested tool contract is returned verbatim`() {
        val options =
            LLMGenerationOptions(
                temperature = 0.4f,
                tool_calling =
                    ToolCallingOptions(
                        max_tool_calls = 2,
                        auto_execute = false,
                        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2,
                    ),
            ).toToolCallingOptions()

        assertEquals(2, options.max_tool_calls)
        assertFalse(assertNotNull(options.auto_execute))
        assertEquals(ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2, options.format)
    }

    @Test
    fun `run loop request inlines sampling and tool routing onto the options`() {
        // idl/tool_calling.proto (tools-collapse-options-and-session-request)
        // collapsed `ToolCallingSessionCreateRequest` to `prompt`/`history`/
        // `options`: max_tokens/temperature/max_tool_calls/format/
        // auto_execute/tool_choice/forced_tool_name/tools/validate_calls all
        // moved exclusively onto the nested `options` (ToolCallingOptions);
        // commons has no top-level sampling knob for the tool loop at all.
        val search = ToolDefinition(name = "search_web", description = "Search current information")
        val request =
            makeToolCallingRunLoopRequest(
                prompt = "Use search_web for the current requirement.",
                options =
                    ToolCallingOptions(
                        tools = listOf(search),
                        max_tool_calls = 2,
                        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2,
                        auto_execute = false,
                        tool_choice = ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC,
                        forced_tool_name = "search_web",
                    ),
                llmOptions =
                    LLMGenerationOptions(
                        max_output_tokens = 96,
                        temperature = 0f,
                        top_p = 1f,
                    ),
                tools = listOf(search),
                validateCalls = null,
            )

        val options = assertNotNull(request.options)
        assertEquals(1f, options.top_p)

        assertEquals(2, options.max_tool_calls)
        assertEquals(ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2, options.format)
        assertFalse(assertNotNull(options.auto_execute))
        assertEquals(ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC, options.tool_choice)
        assertEquals("search_web", options.forced_tool_name)
        assertEquals(listOf("search_web"), options.tools.map { it.name })
        assertEquals(null, options.validate_calls)
    }

    @Test
    fun `run loop request carries multi-turn history onto the request`() {
        val priorTurns = listOf("What is the weather in Paris?", "It is 18C and sunny in Paris.")
        val request =
            makeToolCallingRunLoopRequest(
                prompt = "and in London?",
                options = ToolCallingOptions(tools = emptyList()),
                llmOptions = LLMGenerationOptions(max_output_tokens = 128),
                tools = emptyList(),
                validateCalls = null,
                history = priorTurns,
            )

        assertEquals(priorTurns, request.history.map { it.content })
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
            val result = executor(mapOf("value" to RAToolValue.string("hello")))

            assertEquals("hello", result["echo"]?.string)
            assertEquals(true, result["ok"]?.bool)
        }
    }
}
