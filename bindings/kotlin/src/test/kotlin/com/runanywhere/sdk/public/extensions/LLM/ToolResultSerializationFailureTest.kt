package com.runanywhere.sdk.public.extensions.LLM

import com.runanywhere.sdk.foundation.errors.SDKException
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import io.mockk.verify
import kotlinx.coroutines.runBlocking
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ToolResultSerializationFailureTest {
    @BeforeTest
    fun setUp() {
        mockkStatic("com.runanywhere.sdk.public.extensions.LLM.ToolCallingTypesKt")
    }

    @AfterTest
    fun tearDown() =
        runBlocking {
            ToolCallingOrchestrator.clearTools()
            unmockkStatic("com.runanywhere.sdk.public.extensions.LLM.ToolCallingTypesKt")
        }

    @Test
    fun `failed result serialization reports an error without retrying native serialization`() =
        runBlocking {
            every { RAToolValue.parseObjectJSON(any()) } returns emptyMap()
            every { RAToolValue.jsonString(any()) } throws SDKException.operation("serialization failed")
            ToolCallingOrchestrator.registerTool(ToolDefinition(name = "test-tool", description = "Test", parameters = "{}")) { emptyMap() }

            val result = ToolCallingOrchestrator.executeTool(ToolCall(id = "call-1", name = "test-tool", arguments_json = "{}"))

            assertTrue(result.is_error)
            assertEquals("serialization failed", result.error)
            assertEquals("call-1", result.tool_call_id)
            assertEquals("{}", result.result_json)
            verify(exactly = 1) { RAToolValue.jsonString(any()) }
        }

    @Test
    fun `unknown tool returns an error without calling native serialization`() =
        runBlocking {
            every { RAToolValue.jsonString(any()) } throws SDKException.operation("serialization unavailable")

            val result = ToolCallingOrchestrator.executeTool(ToolCall(id = "call-2", name = "unknown-tool"))

            assertTrue(result.is_error)
            assertEquals("Unknown tool: unknown-tool", result.error)
            verify(exactly = 0) { RAToolValue.jsonString(any()) }
        }

    @Test
    fun `missing JSON response is an explicit serialization failure`() {
        every { any<RAToolValue>().toJSONString(false) } returns null

        assertFailsWith<SDKException> { RAToolValue.jsonString(emptyMap()) }
    }
}
