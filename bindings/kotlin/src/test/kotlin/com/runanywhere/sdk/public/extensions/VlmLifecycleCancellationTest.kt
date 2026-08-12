package com.runanywhere.sdk.public.extensions

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class VlmLifecycleCancellationTest {
    @Test
    fun `lifecycle cancellation reaches native VLM and joins without a late result`() =
        runBlocking {
            val entered = CountDownLatch(1)
            val releaseNative = CountDownLatch(1)
            val cancelCalled = AtomicBoolean(false)
            val delivered = AtomicReference<String?>(null)
            val coordinator = NativeUnaryRequestCoordinator()

            val lifecycleJob =
                launch(Dispatchers.Default) {
                    delivered.set(
                        runCancellableNativeUnaryRequest(
                            coordinator = coordinator,
                            request = { _ ->
                                entered.countDown()
                                releaseNative.await(5, TimeUnit.SECONDS)
                                "stale VLM result"
                            },
                            cancel = { _ ->
                                cancelCalled.set(true)
                                releaseNative.countDown()
                            },
                        ),
                    )
                }

            assertTrue(entered.await(2, TimeUnit.SECONDS))
            lifecycleJob.cancel()
            withTimeout(2_000) { lifecycleJob.cancelAndJoin() }

            assertTrue("lifecycle cancellation must reach native VLM", cancelCalled.get())
            assertFalse("a cancelled VLM result must be invalidated", delivered.get() != null)
        }

    @Test
    fun `completed request does not leave cancellation for an independent request`() =
        runBlocking {
            val cancelCalls = AtomicReference(0)
            val coordinator = NativeUnaryRequestCoordinator()

            assertEquals(
                "first",
                runCancellableNativeUnaryRequest(
                    coordinator = coordinator,
                    request = { _ -> "first" },
                    cancel = { _ -> cancelCalls.set(cancelCalls.get() + 1) },
                ),
            )
            assertEquals(
                "second",
                runCancellableNativeUnaryRequest(
                    coordinator = coordinator,
                    request = { _ -> "second" },
                    cancel = { _ -> cancelCalls.set(cancelCalls.get() + 1) },
                ),
            )
            assertEquals(0, cancelCalls.get())
        }

    @Test
    fun `late stream cancellation cannot cancel its active unary successor`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val activeNativeRequest = AtomicReference<String?>(null)
            val cancelledRequest = AtomicReference<String?>(null)
            val cancellationObserved = CountDownLatch(1)
            val cancelActiveNativeRequest = { _: Long ->
                cancelledRequest.set(activeNativeRequest.get())
                cancellationObserved.countDown()
                Unit
            }

            val stream = coordinator.createLease(cancelActiveNativeRequest)
            stream.enter()
            assertTrue(stream.tryStart())
            activeNativeRequest.set("stream A")

            // Stream A's native call has returned and atomically relinquishes
            // the service before unary B can enter.
            activeNativeRequest.set(null)
            stream.complete()

            val unary = coordinator.createLease(cancelActiveNativeRequest)
            unary.enter()
            assertTrue(unary.tryStart())
            activeNativeRequest.set("unary B")
            // This is the old cross-shape race: stream cleanup arrives after
            // unary B has become the active native request.
            stream.requestCancellation()
            assertEquals(null, cancelledRequest.get())

            val unaryCancellation = launch(Dispatchers.Default) { unary.requestCancellation() }
            try {
                assertTrue(cancellationObserved.await(2, TimeUnit.SECONDS))

                // Legitimate cancellation still reaches the current owner.
                assertEquals("unary B", cancelledRequest.get())
            } finally {
                activeNativeRequest.set(null)
                unary.complete()
                withTimeout(2_000) { unaryCancellation.join() }
            }
        }

    @Test
    fun `cancelling queued unary does not cancel active stream`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val streamCancelCalls = AtomicInteger(0)
            val unaryCancelCalls = AtomicInteger(0)
            val stream = coordinator.createLease { _ -> streamCancelCalls.incrementAndGet() }
            stream.enter()
            assertTrue(stream.tryStart())

            val queuedUnary =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    runCancellableNativeUnaryRequest(
                        coordinator = coordinator,
                        dispatcher = Dispatchers.Unconfined,
                        request = { _ -> error("queued unary must not enter") },
                        cancel = { _ -> unaryCancelCalls.incrementAndGet() },
                    )
                }
            try {
                withTimeout(2_000) { queuedUnary.cancelAndJoin() }
                assertEquals(0, streamCancelCalls.get())
                assertEquals(0, unaryCancelCalls.get())
            } finally {
                stream.complete()
            }
        }

    @Test
    fun `active request dispatches request scoped cancellation exactly once`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val cancelCalls = AtomicInteger(0)
            val request = coordinator.createLease { _ -> cancelCalls.incrementAndGet() }
            request.enter()
            assertTrue(request.tryStart())
            try {
                request.requestCancellation()
                request.requestCancellation()
                coordinator.cancelActive()
                assertEquals(1, cancelCalls.get())
            } finally {
                request.complete()
            }
        }

    @Test
    fun `cancellation after admission but before JNI does not dispatch native cancel`() =
        runBlocking {
            val coordinator = NativeUnaryRequestCoordinator()
            val cancelCalls = AtomicInteger(0)
            val request = coordinator.createLease { _ -> cancelCalls.incrementAndGet() }
            request.enter()
            try {
                request.requestCancellation()
                assertFalse(request.tryStart())
                assertEquals(0, cancelCalls.get())
            } finally {
                request.complete()
            }

            val successor = coordinator.createLease { _ -> cancelCalls.incrementAndGet() }
            successor.enter()
            try {
                assertTrue(successor.tryStart())
                assertEquals(0, cancelCalls.get())
            } finally {
                successor.complete()
            }
        }

    @Test
    fun `blocking JNI cancellation is dispatched off the caller thread`() {
        val callerDispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {
            runBlocking {
                val coordinator = NativeUnaryRequestCoordinator()
                val requestEntered = CountDownLatch(1)
                val releaseRequest = CountDownLatch(1)
                val cancelEntered = CountDownLatch(1)
                val releaseCancel = CountDownLatch(1)
                val callerResponsive = CountDownLatch(1)

                val job =
                    launch(callerDispatcher) {
                        runCancellableNativeUnaryRequest(
                            coordinator = coordinator,
                            dispatcher = Dispatchers.Default,
                            request = { _ ->
                                requestEntered.countDown()
                                releaseRequest.await(5, TimeUnit.SECONDS)
                            },
                            cancel = { _ ->
                                cancelEntered.countDown()
                                releaseCancel.await(5, TimeUnit.SECONDS)
                            },
                        )
                    }

                assertTrue(requestEntered.await(2, TimeUnit.SECONDS))
                job.cancel()
                assertTrue(cancelEntered.await(2, TimeUnit.SECONDS))
                launch(callerDispatcher) { callerResponsive.countDown() }
                assertTrue("caller dispatcher must remain responsive", callerResponsive.await(2, TimeUnit.SECONDS))

                releaseRequest.countDown()
                releaseCancel.countDown()
                withTimeout(2_000) { job.cancelAndJoin() }
            }
        } finally {
            callerDispatcher.close()
        }
    }
}
