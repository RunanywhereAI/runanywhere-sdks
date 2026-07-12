package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ToolDefinition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ToolCallingModelPolicyTest {
    @Test
    fun `512-token LFM is blocked before native tool generation`() {
        val model = model(name = "LFM2.5 230M (HNPU)", contextLength = 512)

        val result = ToolCallingModelPolicy.preflight(
            toolsRequested = true,
            registeredToolCount = 5,
            model = model,
        )

        assertEquals(ToolCallingRoute.BLOCKED, result.route)
        assertFalse(result.availability.isAvailable)
        assertTrue(result.availability.message.orEmpty().contains("512-token context window"))
        assertTrue(result.availability.message.orEmpty().contains("at least 1,024 tokens"))
    }

    @Test
    fun `1024-token Qwen is routed to bounded tool generation`() {
        val result = ToolCallingModelPolicy.preflight(
            toolsRequested = true,
            registeredToolCount = 5,
            model = model(name = "Qwen3.5 0.8B (HNPU)", contextLength = 1_024),
        )

        assertEquals(ToolCallingRoute.TOOL_GENERATION, result.route)
        assertTrue(result.availability.isAvailable)
        assertEquals(null, result.availability.message)
    }

    @Test
    fun `unknown context capability fails closed with an actionable message`() {
        val result = ToolCallingModelPolicy.evaluate(
            model(name = "Unknown model", contextLength = 0),
        )

        assertFalse(result.isAvailable)
        assertTrue(result.message.orEmpty().contains("does not publish"))
        assertTrue(result.message.orEmpty().contains("Choose a model"))
    }

    @Test
    fun `disabled tools preserve normal generation regardless of context`() {
        val result = ToolCallingModelPolicy.preflight(
            toolsRequested = false,
            registeredToolCount = 5,
            model = model(name = "LFM2.5 230M (HNPU)", contextLength = 512),
        )

        assertEquals(ToolCallingRoute.STANDARD_GENERATION, result.route)
    }

    @Test
    fun `empty tool registry preserves normal generation`() {
        val result = ToolCallingModelPolicy.preflight(
            toolsRequested = true,
            registeredToolCount = 0,
            model = model(name = "LFM2.5 230M (HNPU)", contextLength = 512),
        )

        assertEquals(ToolCallingRoute.STANDARD_GENERATION, result.route)
    }

    @Test
    fun `tool execution caps final output and makes sampling greedy without changing system prompt`() {
        val base = ai.runanywhere.proto.v1.LLMGenerationOptions(
            max_tokens = 1_024,
            temperature = 0.7f,
            system_prompt = "Be helpful",
            disable_thinking = false,
        )

        val generation = ToolCallingExecutionPolicy.generationOptions(base)

        assertEquals(ToolCallingExecutionPolicy.MAX_FINAL_RESPONSE_TOKENS, generation.max_tokens)
        assertEquals(0f, generation.temperature)
        assertEquals(1f, generation.top_p)
        assertEquals("Be helpful", generation.system_prompt)
        assertTrue(generation.disable_thinking)
        assertEquals(45_000L, ToolCallingExecutionPolicy.TIMEOUT_MILLIS)
    }

    @Test
    fun `tool execution preserves a smaller user token budget`() {
        val generation = ToolCallingExecutionPolicy.generationOptions(
            ai.runanywhere.proto.v1.LLMGenerationOptions(max_tokens = 64),
        )

        assertEquals(64, generation.max_tokens)
    }

    @Test
    fun `execution plan preserves registry for shared native routing`() {
        val tools = builtInTools()

        val plan = ToolCallingExecutionPolicy.plan(
            base = ai.runanywhere.proto.v1.LLMGenerationOptions(max_tokens = 64),
            registeredTools = tools,
        )

        assertEquals(tools, plan.toolOptions.tools)
        assertEquals(null, plan.toolChoice)
        assertEquals(null, plan.forcedToolName)
        assertEquals(ToolCallingExecutionPolicy.MAX_TOOL_CALLS, plan.toolOptions.max_tool_calls)
        assertEquals(64, plan.generationOptions.max_tokens)
        assertEquals(64, plan.toolOptions.max_tokens)
        assertEquals(0f, plan.toolOptions.temperature)
        assertTrue(plan.toolOptions.disable_thinking == true)
        assertFalse(plan.toolOptions.keep_tools_available)
    }

    private fun model(name: String, contextLength: Int): ModelInfo = ModelInfo(
        id = name.lowercase().replace(' ', '-'),
        name = name,
        context_length = contextLength,
    )

    private fun builtInTools(): List<ToolDefinition> = listOf(
        ToolDefinition(name = "get_current_time", description = "Current time"),
        ToolDefinition(name = "calculate", description = "Evaluate an expression"),
        ToolDefinition(name = "search_web", description = "Search current information"),
    )
}
