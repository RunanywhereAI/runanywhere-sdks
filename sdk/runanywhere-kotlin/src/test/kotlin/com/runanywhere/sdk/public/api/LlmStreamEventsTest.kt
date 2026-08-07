/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Characterizes the native-stream-completion contract for
 * `RunAnywhere.llm.generateStream` under the v4 public API spec: a stream
 * never fabricates a successful `completed`. A native call that resolves
 * without ever sending a COMPLETED/ERROR terminal `event_kind` emits
 * `failed` instead (mirrors Swift's `RunAnywhere.mapGenerationStream` in
 * `runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/LLMNamespace.swift`).
 * [mapLLMStreamEvents] is the injectable core [LlmNamespace.streamEvents]
 * delegates to, so these tests exercise the real fold logic without a JNI bridge.
 *
 * `RALLMStreamEvent.is_final` is deleted outright (idl/llm_service.proto):
 * `event_kind` (COMPLETED/ERROR) is the sole terminal discriminator now, and
 * `finish_reason` was retyped from a plain string to the `FinishReason` enum.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.FinishReason
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.LLMStreamEventKind
import ai.runanywhere.proto.v1.SDKError
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
    fun `native stream ending without a terminal event_kind emits failed instead of fabricating a completion`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(token = "Hel", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN),
                    LLMStreamEvent(token = "lo", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN),
                    // Native call resolves here without ever sending event_kind = COMPLETED.
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
            assertTrue(
                failed.error.message
                    .orEmpty()
                    .contains("terminal event"),
            )
        }

    @Test
    fun `a terminal COMPLETED event still wins and is not double-emitted`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(token = "Hi", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN),
                    LLMStreamEvent(
                        token = "",
                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED,
                        finish_reason = FinishReason.FINISH_REASON_STOP,
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
                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING,
                    ),
                    LLMStreamEvent(
                        token = "answer",
                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED,
                        finish_reason = FinishReason.FINISH_REASON_STOP,
                    ),
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
                    LLMStreamEvent(token = "partial", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN),
                    LLMStreamEvent(
                        token = "",
                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR,
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
            assertTrue(
                failed.error.message
                    .orEmpty()
                    .contains("backend crashed"),
            )
        }
}
