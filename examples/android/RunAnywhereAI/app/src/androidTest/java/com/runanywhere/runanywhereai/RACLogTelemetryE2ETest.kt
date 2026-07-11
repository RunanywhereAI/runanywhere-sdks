package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.EventCategory
import ai.runanywhere.proto.v1.SDKEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Events.subscribeSDKEvents
import com.runanywhere.sdk.public.extensions.Events.unsubscribeSDKEvents
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class RACLogTelemetryE2ETest {
    @Test
    fun warningTraversesAppReporterAndNativeEventPipeline() {
        runBlocking {
            withTimeout(60_000) { GlobalState.awaitBootstrapComplete() }
        }

        val marker = "raclog-telemetry-e2e"
        val received = AtomicReference<SDKEvent>()
        val receivedLatch = CountDownLatch(1)
        val subscription =
            RunAnywhere.subscribeSDKEvents { event ->
                if (
                    event.operation_id == "raclog.warning" &&
                    event.error?.message?.contains(marker) == true
                ) {
                    received.compareAndSet(null, event)
                    receivedLatch.countDown()
                }
            }
        assertTrue("Native SDK-event subscription must be available", subscription > 0L)

        try {
            RACLog.w(marker)
            assertTrue(
                "RACLog warning must return through the native SDK-event stream",
                receivedLatch.await(10, TimeUnit.SECONDS),
            )
            val event = checkNotNull(received.get())

            assertEquals(EventCategory.EVENT_CATEGORY_FAILURE, event.category)
            assertEquals(ErrorCode.ERROR_CODE_PROCESSING_FAILED, event.error?.code)
            assertEquals(true, event.failure?.recoverable)
            assertEquals("raclog.warning", event.operation_id)
        } finally {
            RunAnywhere.unsubscribeSDKEvents(subscription)
        }
    }
}
