/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Characterizes the native-stream-completion contract for
 * `RunAnywhere.llm.generateStream` under the v4 public API spec: a stream
 * never fabricates a successful `completed`. A native call that resolves
 * without ever sending an `is_final` proto event emits `failed` instead
 * (mirrors Swift's `RunAnywhere.mapGenerationStream` in
 * `runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/LLMNamespace.swift`).
 * [mapLLMStreamEvents] is the injectable core [LlmNamespace.streamEvents]
 * delegates to, so these tests exercise the real fold logic without a JNI bridge.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.SDKError
import ai.runanywhere.proto.v1.TokenKind
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LlmStreamEventsTest {
    @Test
    fun `native stream ending without is_final emits failed instead of fabricating a completion`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(token = "Hel", is_final = false),
                    LLMStreamEvent(token = "lo", is_final = false),
                    // Native call resolves here without ever sending is_final = true.
                )

            val events = mapLLMStreamEvents("req-1", "model-a", raw).toList()

            assertEquals(
                listOf(
                    GenerationEvent.Started::class,
                    GenerationEvent.TextDelta::class,
                    GenerationEvent.TextDelta::class,
                    GenerationEvent.Failed::class,
                ),
                events.map { it::class },
            )
            val failed = events.last() as GenerationEvent.Failed
            assertEquals("Hello", failed.partial)
            assertTrue(failed.error.message.orEmpty().contains("terminal event"))
        }

    @Test
    fun `a terminal is_final event still wins and is not double-emitted`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(token = "Hi", is_final = false),
                    LLMStreamEvent(
                        token = "",
                        is_final = true,
                        finish_reason = "stop",
                    ),
                )

            val events = mapLLMStreamEvents("req-2", "model-a", raw).toList()

            assertEquals(
                listOf(
                    GenerationEvent.Started::class,
                    GenerationEvent.TextDelta::class,
                    GenerationEvent.Completed::class,
                ),
                events.map { it::class },
            )
            val completed = events.last() as GenerationEvent.Completed
            assertEquals("Hi", completed.result.text)
        }

    @Test
    fun `native stream that produces zero events fails instead of synthesizing an empty completion`() =
        runBlocking {
            val raw = flowOf<LLMStreamEvent>()

            try {
                mapLLMStreamEvents("req-3", "model-a", raw).toList()
                fail("expected an SDKException")
            } catch (e: SDKException) {
                assertTrue(e.message.orEmpty().contains("before producing any output"))
            }
        }

    @Test
    fun `thinking tokens are folded into thinkingText on a terminal completion`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(
                        token = "thinking...",
                        is_final = false,
                        kind = TokenKind.TOKEN_KIND_THOUGHT,
                    ),
                    LLMStreamEvent(token = "answer", is_final = true, finish_reason = "stop"),
                )

            val events = mapLLMStreamEvents("req-4", "model-a", raw).toList()
            val completed = events.last() as GenerationEvent.Completed
            assertEquals("thinking...", completed.result.thinkingText)
        }

    @Test
    fun `an in-flight error event emits failed rather than a fabricated completion`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(token = "partial", is_final = false),
                    LLMStreamEvent(
                        token = "",
                        is_final = false,
                        error = SDKError(message = "backend crashed"),
                    ),
                )

            val events = mapLLMStreamEvents("req-5", "model-a", raw).toList()

            assertEquals(
                listOf(
                    GenerationEvent.Started::class,
                    GenerationEvent.TextDelta::class,
                    GenerationEvent.Failed::class,
                ),
                events.map { it::class },
            )
            val failed = events.last() as GenerationEvent.Failed
            assertTrue(failed.error.message.orEmpty().contains("backend crashed"))
        }
}
