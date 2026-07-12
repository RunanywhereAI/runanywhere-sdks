/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.LLMStreamFinalResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class RunAnywhereTextGenerationStreamTest {
    @Test
    fun `synchronous callback burst is lossless for a stalled collector and aggregates exactly`() =
        runBlocking {
            val tokenCount = 2_048
            val expectedText =
                buildString {
                    repeat(tokenCount) { index -> append("<$index>") }
                }
            val productionFinished = CompletableDeferred<Unit>()
            val cancelCalls = AtomicInteger(0)

            val events =
                losslessLLMStreamFlow(
                    prepare = {},
                    generate = { onEvent ->
                        repeat(tokenCount) { index ->
                            assertTrue(
                                "native callback must accept token $index",
                                onEvent(
                                    LLMStreamEvent(
                                        seq = index.toLong() + 1,
                                        token = "<$index>",
                                    ),
                                ),
                            )
                        }
                        assertFalse(
                            "terminal callback must stop native generation",
                            onEvent(
                                LLMStreamEvent(
                                    seq = tokenCount.toLong() + 1,
                                    is_final = true,
                                    finish_reason = "stop",
                                ),
                            ),
                        )
                        productionFinished.complete(Unit)
                    },
                    cancel = { cancelCalls.incrementAndGet() },
                )

            val observedSequences = mutableListOf<Long>()
            val deliberatelyStalledEvents =
                events.onEach { event ->
                    if (observedSequences.isEmpty()) {
                        // Hold the collector on event 1 until the synchronous
                        // producer has enqueued all 2,049 events. This creates
                        // deterministic pressure far beyond callbackFlow's
                        // default capacity (64), without timing assumptions.
                        withTimeout(2_000) { productionFinished.await() }
                    }
                    observedSequences += event.seq
                }

            val result =
                aggregateLLMStream(
                    prompt = "test",
                    events = deliberatelyStalledEvents,
                    onToken = null,
                    resolveModelIdentity = {
                        LLMStreamModelIdentity(
                            modelID = "stress-model",
                            framework = "stress-framework",
                        )
                    },
                    nowMillis = { 10_000L },
                )

            assertEquals((1L..tokenCount.toLong() + 1).toList(), observedSequences)
            assertEquals(expectedText, result.text)
            assertEquals(tokenCount, result.tokens_generated)
            assertEquals(tokenCount, result.response_tokens)
            assertEquals(tokenCount + 1, result.total_tokens)
            assertEquals("stop", result.finish_reason)
            assertEquals("stress-model", result.model_used)
            assertEquals("stress-framework", result.framework)
            assertNull(result.error_message)
            assertEquals(0, cancelCalls.get())
        }

    @Test
    fun `terminal canonical result wins without changing metrics`() =
        runBlocking {
            val canonical =
                LLMStreamFinalResult(
                    text = "canonical answer",
                    thinking_content = "canonical reasoning",
                    prompt_tokens = 7,
                    completion_tokens = 9,
                    total_tokens = 16,
                    total_time_ms = 123L,
                    time_to_first_token_ms = 8L,
                    tokens_per_second = 45.5f,
                    prompt_eval_time_ms = 20L,
                    decode_time_ms = 100L,
                )
            val events =
                flowOf(
                    LLMStreamEvent(seq = 1, token = "streamed fallback"),
                    LLMStreamEvent(
                        seq = 2,
                        is_final = true,
                        finish_reason = "stop",
                        result = canonical,
                    ),
                )

            val result =
                aggregateLLMStream(
                    prompt = "ignored",
                    events = events,
                    onToken = null,
                    resolveModelIdentity = {
                        LLMStreamModelIdentity(
                            modelID = "canonical-model",
                            framework = "qhexrt",
                        )
                    },
                    nowMillis = { 42L },
                )

            assertEquals("canonical answer", result.text)
            assertEquals("canonical reasoning", result.thinking_content)
            assertEquals(7, result.input_tokens)
            assertEquals(9, result.tokens_generated)
            assertEquals(9, result.response_tokens)
            assertEquals(16, result.total_tokens)
            assertEquals(123.0, result.generation_time_ms, 0.0)
            assertEquals(8.0, result.ttft_ms!!, 0.0)
            assertEquals(45.5, result.tokens_per_second, 0.0)
            assertEquals(20L, result.prompt_eval_time_ms)
            assertEquals(100L, result.decode_time_ms)
            assertEquals("stop", result.finish_reason)
            assertEquals("canonical-model", result.model_used)
            assertEquals("qhexrt", result.framework)
        }

    @Test
    fun `collector cancellation makes the callback reject further events`() =
        runBlocking {
            val continueAfterCancellation = CountDownLatch(1)
            val callbackAfterCancellation = CompletableDeferred<Boolean>()
            val cancelCalls = AtomicInteger(0)
            val events =
                losslessLLMStreamFlow(
                    prepare = {},
                    generate = { onEvent ->
                        assertTrue(onEvent(LLMStreamEvent(seq = 1, token = "first")))
                        assertTrue(
                            "cancellation hook did not release producer",
                            continueAfterCancellation.await(2, TimeUnit.SECONDS),
                        )
                        callbackAfterCancellation.complete(
                            onEvent(LLMStreamEvent(seq = 2, token = "must-not-deliver")),
                        )
                    },
                    cancel = {
                        cancelCalls.incrementAndGet()
                        continueAfterCancellation.countDown()
                    },
                )

            assertEquals(listOf("first"), events.take(1).toList().map { it.token })
            assertFalse(withTimeout(2_000) { callbackAfterCancellation.await() })
            assertEquals(1, cancelCalls.get())
        }
}
