package com.runanywhere.sdk.public.extensions

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class RagCancellationTest {
    @Test
    fun `coroutine cancellation interrupts native query and discards late result`() =
        runBlocking {
            val started = CountDownLatch(1)
            val releaseNative = CountDownLatch(1)
            val cancelCalled = AtomicBoolean(false)
            val delivered = AtomicReference<String?>(null)
            val coordinator = NativeUnaryRequestCoordinator()

            val job =
                launch(Dispatchers.Default) {
                    delivered.set(
                        runCancellableNativeRagQuery(
                            dispatcher = Dispatchers.IO,
                            coordinator = coordinator,
                            query = { _ ->
                                started.countDown()
                                releaseNative.await(5, TimeUnit.SECONDS)
                                "stale native answer"
                            },
                            cancel = { _ ->
                                cancelCalled.set(true)
                                releaseNative.countDown()
                            },
                        ),
                    )
                }

            assertTrue(started.await(2, TimeUnit.SECONDS))
            job.cancel()
            withTimeout(2_000) { job.cancelAndJoin() }

            assertTrue(cancelCalled.get())
            assertFalse("a cancelled native answer must not be delivered", delivered.get() != null)
        }

    @Test
    fun `queued query captures the RAG session only after lifecycle admission`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val sessionHandle = AtomicLong(1L)
            val lifecycleEntered = CountDownLatch(1)
            val releaseLifecycle = CountDownLatch(1)
            val queryEntered = CountDownLatch(1)
            val capturedHandle = AtomicLong(0L)

            val lifecycle =
                launch(Dispatchers.Default) {
                    coordinator.withExclusiveOperation(Dispatchers.Default) {
                        lifecycleEntered.countDown()
                        releaseLifecycle.await(5, TimeUnit.SECONDS)
                        sessionHandle.set(2L)
                    }
                }
            assertTrue(lifecycleEntered.await(2, TimeUnit.SECONDS))

            val query =
                launch(Dispatchers.Default) {
                    runCancellableNativeRagQuery<String>(
                        dispatcher = Dispatchers.Default,
                        coordinator = coordinator,
                        query = { _ ->
                            capturedHandle.set(sessionHandle.get())
                            queryEntered.countDown()
                            "answer"
                        },
                        cancel = {},
                    )
                }

            assertFalse(
                "query must remain queued while lifecycle owns the RAG gate",
                queryEntered.await(100, TimeUnit.MILLISECONDS),
            )
            releaseLifecycle.countDown()
            withTimeout(2_000) { joinAll(lifecycle, query) }

            assertEquals(2L, capturedHandle.get())
        }

    @Test
    fun `RAG lifecycle cancellation drains the active query before session mutation`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val queryEntered = CountDownLatch(1)
            val releaseQuery = CountDownLatch(1)
            val cancelRequested = CountDownLatch(1)
            val lifecycleOwnsGate = CountDownLatch(1)
            val releaseLifecycle = CountDownLatch(1)
            val successorEntered = CountDownLatch(1)
            val queryReturned = AtomicBoolean(false)
            val lifecycleEntered = AtomicBoolean(false)

            val query =
                launch(Dispatchers.Default) {
                    runCancellableNativeRagQuery<String>(
                        dispatcher = Dispatchers.Default,
                        coordinator = coordinator,
                        query = { _ ->
                            queryEntered.countDown()
                            releaseQuery.await(5, TimeUnit.SECONDS)
                            queryReturned.set(true)
                            "cancelled answer"
                        },
                        cancel = {
                            cancelRequested.countDown()
                            releaseQuery.countDown()
                        },
                    )
                }
            assertTrue(queryEntered.await(2, TimeUnit.SECONDS))

            val lifecycle =
                launch(Dispatchers.Default) {
                    coordinator.withExclusiveOperation(
                        dispatcher = Dispatchers.Default,
                        interruptActiveRequest = true,
                    ) {
                        lifecycleEntered.set(true)
                        lifecycleOwnsGate.countDown()
                        assertTrue(
                            "active query must relinquish the gate before lifecycle mutation",
                            queryReturned.get(),
                        )
                        releaseLifecycle.await(5, TimeUnit.SECONDS)
                    }
                }

            assertTrue(cancelRequested.await(2, TimeUnit.SECONDS))
            val successor =
                launch(Dispatchers.Default) {
                    runCancellableNativeRagQuery<String>(
                        dispatcher = Dispatchers.Default,
                        coordinator = coordinator,
                        query = { _ ->
                            successorEntered.countDown()
                            "successor"
                        },
                        cancel = {},
                    )
                }
            assertTrue(lifecycleOwnsGate.await(2, TimeUnit.SECONDS))
            assertFalse(
                "successor query must stay behind the queued lifecycle mutation",
                successorEntered.await(100, TimeUnit.MILLISECONDS),
            )
            releaseLifecycle.countDown()
            withTimeout(2_000) { joinAll(query, lifecycle, successor) }
            assertTrue(lifecycleEntered.get())
        }
}
