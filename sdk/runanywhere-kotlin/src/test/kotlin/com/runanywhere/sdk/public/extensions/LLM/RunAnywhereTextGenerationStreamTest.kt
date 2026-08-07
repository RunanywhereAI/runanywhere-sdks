/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * `RALLMStreamEvent.is_final` and `LLMStreamFinalResult` are deleted outright
 * (idl/llm_service.proto): `event_kind` (COMPLETED/ERROR) is the sole
 * terminal discriminator now, `finish_reason` was retyped from a plain
 * string to the `FinishReason` enum, and the terminal canonical payload is
 * carried on `LLMStreamEvent.result` as a plain `LLMGenerationResult`
 * (the same message every non-streaming call returns) rather than a
 * dedicated final-result type. `TokenUsage.tokens_per_second` was renamed
 * `decode_tokens_per_second`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.FinishReason
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.LLMStreamEventKind
import ai.runanywhere.proto.v1.TokenUsage
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
                                        token = "<$index>",
                                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN,
                                    ),
                                ),
                            )
                        }
                        assertFalse(
                            "terminal callback must stop native generation",
                            onEvent(
                                LLMStreamEvent(
                                    event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED,
                                    finish_reason = FinishReason.FINISH_REASON_STOP,
                                ),
                            ),
                        )
                        productionFinished.complete(Unit)
                    },
                    cancel = { cancelCalls.incrementAndGet() },
                )

            var observedCount = 0
            val deliberatelyStalledEvents =
                events.onEach {
                    if (observedCount == 0) {
                        // Hold the collector on event 1 until the synchronous
                        // producer has enqueued all 2,049 events. This creates
                        // deterministic pressure far beyond callbackFlow's
                        // default capacity (64), without timing assumptions.
                        withTimeout(2_000) { productionFinished.await() }
                    }
                    observedCount += 1
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

            assertEquals(tokenCount + 1, observedCount)
            assertEquals(expectedText, result.text)
            val usage = result.usage!!
            assertEquals(tokenCount, usage.output_tokens)
            assertEquals(tokenCount, result.response_tokens)
            assertEquals(tokenCount + 1, usage.total_tokens)
            assertEquals(FinishReason.FINISH_REASON_STOP, result.finish_reason)
            assertEquals("stress-model", result.model_used)
            assertEquals("stress-framework", result.framework)
            assertNull(result.error)
            assertEquals(0, cancelCalls.get())
        }

    @Test
    fun `terminal canonical result wins without changing metrics`() =
        runBlocking {
            val canonical =
                LLMGenerationResult(
                    text = "canonical answer",
                    thinking_content = "canonical reasoning",
                    generation_time_ms = 123.0,
                    prompt_eval_time_ms = 20L,
                    decode_time_ms = 100L,
                    usage =
                        TokenUsage(
                            input_tokens = 7,
                            output_tokens = 9,
                            total_tokens = 16,
                            decode_tokens_per_second = 45.5,
                            ttft_ms = 8L,
                        ),
                )
            val events =
                flowOf(
                    LLMStreamEvent(token = "streamed fallback", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN),
                    LLMStreamEvent(
                        event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED,
                        finish_reason = FinishReason.FINISH_REASON_STOP,
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
            val usage = result.usage!!
            assertEquals(7, usage.input_tokens)
            assertEquals(9, usage.output_tokens)
            assertEquals(9, result.response_tokens)
            assertEquals(16, usage.total_tokens)
            assertEquals(123.0, result.generation_time_ms, 0.0)
            assertEquals(8L, usage.ttft_ms)
            assertEquals(45.5, usage.decode_tokens_per_second, 0.0)
            assertEquals(20L, result.prompt_eval_time_ms)
            assertEquals(100L, result.decode_time_ms)
            assertEquals(FinishReason.FINISH_REASON_STOP, result.finish_reason)
            assertEquals("canonical-model", result.model_used)
            assertEquals("qhexrt", result.framework)
        }

    @Test
    fun `batch buffered maple metrics use wall throughput and clear fake ttft`() {
        // 182 tokens, 13685 ms wall, "TTFT" 13680 ms, flush window 5 ms →
        // naive decode rate ≈ 36400 tok/s. Sanitizer must report ~13.3 tok/s
        // and drop the stream-derived TTFT (it is not prefill).
        val metrics =
            sanitizeStreamMetrics(
                totalMs = 13_685.0,
                outputTokens = 182,
                reportedTps = 36_400.0,
                reportedTtftMs = 13_680L,
            )
        assertEquals(0L, metrics.ttftMs)
        assertEquals(182 * 1000.0 / 13_685.0, metrics.decodeTokensPerSecond, 0.05)
    }

    @Test
    fun `absurd tok rate without ttft still falls back to wall throughput`() {
        val metrics =
            sanitizeStreamMetrics(
                totalMs = 15_339.0,
                outputTokens = 179,
                reportedTps = 179_000.0,
                reportedTtftMs = null,
            )
        assertEquals(0L, metrics.ttftMs)
        assertEquals(179 * 1000.0 / 15_339.0, metrics.decodeTokensPerSecond, 0.05)
    }

    @Test
    fun `batch buffered terminal result is sanitized in aggregateLLMStream`() =
        runBlocking {
            val bogus =
                LLMGenerationResult(
                    text = "Paris",
                    generation_time_ms = 13_685.0,
                    prompt_eval_time_ms = 13_680L,
                    decode_time_ms = 5L,
                    usage =
                        TokenUsage(
                            input_tokens = 73,
                            output_tokens = 182,
                            total_tokens = 255,
                            decode_tokens_per_second = 36_400.0,
                            ttft_ms = 13_680L,
                        ),
                )
            var tick = 0L
            val result =
                aggregateLLMStream(
                    prompt = "capital of France",
                    events =
                        flowOf(
                            LLMStreamEvent(
                                token = "Paris",
                                event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN,
                            ),
                            LLMStreamEvent(
                                event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED,
                                finish_reason = FinishReason.FINISH_REASON_STOP,
                                result = bogus,
                            ),
                        ),
                    onToken = null,
                    resolveModelIdentity = {
                        LLMStreamModelIdentity(modelID = "maple", framework = "qhexrt")
                    },
                    nowMillis = { tick++ },
                )
            val usage = result.usage!!
            assertEquals(0L, usage.ttft_ms)
            assertEquals(182 * 1000.0 / 13_685.0, usage.decode_tokens_per_second, 0.05)
            assertEquals(13_685.0, result.generation_time_ms, 0.0)
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
                        assertTrue(
                            onEvent(LLMStreamEvent(token = "first", event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN)),
                        )
                        assertTrue(
                            "cancellation hook did not release producer",
                            continueAfterCancellation.await(2, TimeUnit.SECONDS),
                        )
                        callbackAfterCancellation.complete(
                            onEvent(
                                LLMStreamEvent(
                                    token = "must-not-deliver",
                                    event_kind = LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN,
                                ),
                            ),
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
