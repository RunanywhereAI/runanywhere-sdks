/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Characterizes lossless native→Flow delivery for LLM streaming. Aggregate
 * helpers (`aggregateStream` / `aggregateLLMStream`) are deleted; callers
 * collect `RunAnywhere.llm.generateStream` and read `GenerationEvent.Completed`
 * (see [LlmStreamEventsTest]).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.FinishReason
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.LLMStreamEventKind
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class RunAnywhereTextGenerationStreamTest {
    @Test
    fun `synchronous callback burst is lossless for a stalled collector`() =
        runBlocking {
            val tokenCount = 2_048
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
            events
                .onEach {
                    if (observedCount == 0) {
                        withTimeout(2_000) { productionFinished.await() }
                    }
                    observedCount += 1
                }.toList()

            assertEquals(tokenCount + 1, observedCount)
            assertEquals(0, cancelCalls.get())
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
