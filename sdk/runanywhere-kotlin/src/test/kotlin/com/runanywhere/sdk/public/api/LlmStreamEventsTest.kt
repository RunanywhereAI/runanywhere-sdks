/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Characterizes and locks in the native-stream-completion contract for
 * `RunAnywhere.llm.generateStream` (PR #605 review issue #4).
 *
 * The native boundary can legitimately resolve a stream call without ever
 * sending an `is_final` proto event. Swift treats that as a successful
 * completion and synthesizes a wall-clock result
 * (`RunAnywhere.synthesizeResult` in
 * `runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/LLMNamespace.swift`)
 * rather than throwing, as long as at least one native event was observed.
 * [mapLLMStreamEvents] is the injectable core [LlmNamespace.streamEvents]
 * delegates to, so these tests exercise the real fold/synthesis logic
 * without a JNI bridge.
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
    fun `characterization -- native stream ending without is_final synthesizes a completion instead of stopping silently`() =
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
                    GenerationEvent.Token::class,
                    GenerationEvent.Token::class,
                    GenerationEvent.Completed::class,
                ),
                events.map { it::class },
            )
            val completed = events.last() as GenerationEvent.Completed
            assertEquals("Hello", completed.result.text)
            assertEquals(2, completed.result.outputTokens)
            assertEquals(FinishReason.STOP, completed.result.finishReason)
            assertEquals("req-1", completed.result.requestId)
            assertEquals("model-a", completed.result.model)
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
                    GenerationEvent.Token::class,
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
    fun `thinking tokens are folded into thinkingText on a synthesized completion`() =
        runBlocking {
            val raw =
                flowOf(
                    LLMStreamEvent(
                        token = "thinking...",
                        is_final = false,
                        kind = TokenKind.TOKEN_KIND_THOUGHT,
                    ),
                    LLMStreamEvent(token = "answer", is_final = false),
                )

            val events = mapLLMStreamEvents("req-4", "model-a", raw).toList()
            val completed = events.last() as GenerationEvent.Completed
            assertEquals("answer", completed.result.text)
            assertEquals("thinking...", completed.result.thinkingText)
        }

    @Test
    fun `an in-flight error event still throws instead of being swallowed by synthesis`() =
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

            try {
                mapLLMStreamEvents("req-5", "model-a", raw).toList()
                fail("expected an SDKException")
            } catch (e: SDKException) {
                assertTrue(e.message.orEmpty().contains("backend crashed"))
            }
        }
}
