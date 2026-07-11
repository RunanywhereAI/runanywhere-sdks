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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RagCancellationTest {
    @Test
    fun `coroutine cancellation interrupts native query and discards late result`() = runBlocking {
        val started = CountDownLatch(1)
        val releaseNative = CountDownLatch(1)
        val cancelCalled = AtomicBoolean(false)
        val delivered = AtomicReference<String?>(null)

        val job = launch(Dispatchers.Default) {
            delivered.set(
                runCancellableNativeRagQuery(
                    dispatcher = Dispatchers.IO,
                    query = {
                        started.countDown()
                        releaseNative.await(5, TimeUnit.SECONDS)
                        "stale native answer"
                    },
                    cancel = {
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
}
