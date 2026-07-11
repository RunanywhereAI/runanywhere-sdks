package com.runanywhere.sdk.public.extensions

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VlmLifecycleCancellationTest {
    @Test
    fun `lifecycle cancellation reaches native VLM and joins without a late result`() =
        runBlocking {
            val entered = CountDownLatch(1)
            val releaseNative = CountDownLatch(1)
            val cancelCalled = AtomicBoolean(false)
            val delivered = AtomicReference<String?>(null)

            val lifecycleJob =
                launch(Dispatchers.Default) {
                    delivered.set(
                        runCancellableNativeUnaryRequest(
                            request = {
                                entered.countDown()
                                releaseNative.await(5, TimeUnit.SECONDS)
                                "stale VLM result"
                            },
                            cancel = {
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

            assertEquals(
                "first",
                runCancellableNativeUnaryRequest(
                    request = { "first" },
                    cancel = { cancelCalls.set(cancelCalls.get() + 1) },
                ),
            )
            assertEquals(
                "second",
                runCancellableNativeUnaryRequest(
                    request = { "second" },
                    cancel = { cancelCalls.set(cancelCalls.get() + 1) },
                ),
            )
            assertEquals(0, cancelCalls.get())
        }
}
