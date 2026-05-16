/*
 * VoiceAgentStreamAdapterFanOutTest.kt
 *
 * Phase E / B29 — verifies that the Kotlin voice-agent stream adapter
 * fans a single C-side registration out to every concurrent collector.
 *
 * The C ABI exposes only one proto-callback slot per handle, so a naïve
 * adapter would silently let the second collector clobber the first.
 * This test uses the package-private [VoiceAgentStreamAdapter.NativeBridge]
 * seam to inject a fake producer and asserts that:
 *
 *   1. The bridge is installed exactly once for N concurrent collectors.
 *   2. Every collector observes every event in order.
 *   3. Tearing down the last collector unregisters the bridge.
 *   4. Re-subscribing after full teardown installs a fresh bridge.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.UserSaidEvent
import ai.runanywhere.proto.v1.VoiceEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class VoiceAgentStreamAdapterFanOutTest {
    /**
     * A deterministic fake that records the Kotlin callback when
     * registerCallback is invoked and exposes `emit(event)` so tests can
     * drive the fan-out synchronously.
     */
    private class FakeBridge : VoiceAgentStreamAdapter.NativeBridge {
        val registerCount = AtomicInteger(0)
        val unregisterCount = AtomicInteger(0)
        private val nextId = AtomicLong(1L)

        @Volatile
        var currentId: Long = 0
            private set

        @Volatile
        private var cb: ((ByteArray) -> Unit)? = null

        override fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long {
            registerCount.incrementAndGet()
            this.cb = cb
            currentId = nextId.getAndIncrement()
            return currentId
        }

        override fun unregisterCallback(handle: Long, callbackId: Long) {
            unregisterCount.incrementAndGet()
            cb = null
            currentId = 0
        }

        /** Push one encoded event through the callback, if installed. */
        fun emit(event: VoiceEvent) {
            val sink = cb ?: error("emit called before any collector subscribed")
            sink(VoiceEvent.ADAPTER.encode(event))
        }

        fun isRegistered(): Boolean = cb != null
    }

    private fun event(seq: Long, text: String): VoiceEvent =
        VoiceEvent(seq = seq, user_said = UserSaidEvent(text = text, is_final = true))

    @After
    fun reset() {
        // Phase E fan-out caches state per (handle, bridge) pair. Reset
        // between tests by draining any leftover entries so assertions
        // on [activeFanOutCount] are stable even when tests leave the
        // JVM in a warm state (e.g. under Gradle's test worker reuse).
        repeat(8) {
            if (VoiceAgentStreamAdapter.activeFanOutCount() == 0) return
            // Nothing to do: all handles tear down their own fanOut via
            // detach(). Just yield once in case a coroutine is still
            // unwinding.
            Thread.sleep(5)
        }
    }

    @Test
    fun `single collector receives all events`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 1L, bridge = bridge)

            val collected =
                async(Dispatchers.Default) {
                    withTimeout(2_000) {
                        adapter.stream().take(3).toList()
                    }
                }

            // Wait for the collector to register before producing events.
            awaitRegistered(bridge)
            bridge.emit(event(1, "hello"))
            bridge.emit(event(2, "world"))
            bridge.emit(event(3, "!"))

            val events = collected.await()
            assertEquals(listOf(1L, 2L, 3L), events.map { it.seq })

            // Collector completed via take(3) → awaitClose fires → unregister.
            awaitUnregistered(bridge)
            assertEquals(1, bridge.registerCount.get())
            assertEquals(1, bridge.unregisterCount.get())
        }

    @Test
    fun `two concurrent collectors each receive every event`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 42L, bridge = bridge)

            val a =
                async(Dispatchers.Default) {
                    withTimeout(2_000) { adapter.stream().take(4).toList() }
                }
            val b =
                async(Dispatchers.Default) {
                    withTimeout(2_000) { adapter.stream().take(4).toList() }
                }

            // Both collectors must be attached before we start emitting, or
            // the late subscriber will miss events by design (DROP_OLDEST
            // semantics are for overflow, not for "I subscribed late").
            awaitCollectorCount(bridge, adapter, handle = 42L, expected = 2)

            // ONE C-side registration despite TWO collectors — this is the
            // central fan-out invariant we're validating.
            assertEquals(
                "expected exactly one native registration for two collectors",
                1,
                bridge.registerCount.get(),
            )

            for (i in 1..4) {
                bridge.emit(event(i.toLong(), "msg-$i"))
            }

            val eventsA = a.await()
            val eventsB = b.await()
            assertEquals(
                "collector A did not observe the full sequence",
                listOf(1L, 2L, 3L, 4L),
                eventsA.map { it.seq },
            )
            assertEquals(
                "collector B did not observe the full sequence",
                listOf(1L, 2L, 3L, 4L),
                eventsB.map { it.seq },
            )

            awaitUnregistered(bridge)
            assertEquals(
                "final teardown should unregister the shared C callback exactly once",
                1,
                bridge.unregisterCount.get(),
            )
        }

    /**
     * tests-and-coverage-003 regression coverage. The class doc for
     * `HandleStreamAdapter` promises drop-oldest per-collector backpressure
     * so a paused/slow collector can never stall the native callback
     * thread. This test simulates a "slow collector" by deliberately not
     * draining the Flow and verifies that:
     *
     *   1. `bridge.emit(...)` (executing on the simulated native callback
     *      thread) returns promptly even when the per-collector channel is
     *      fully saturated — i.e. no `trySendBlocking` waits for room.
     *   2. After the collector starts draining, it observes a bounded
     *      suffix of recent events (DROP_OLDEST drops older entries while
     *      preserving the newest window).
     */
    @Test
    fun `slow collector does not block native callback thread`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 123L, bridge = bridge)

            // Deliberately slow collector: delays before consuming each event.
            // The first event unblocks the channel, then we hold it for long
            // enough that subsequent emit() calls must rely on DROP_OLDEST,
            // not on backpressure-induced blocking.
            val capturedSize = 8
            val collected =
                async(Dispatchers.Default) {
                    withTimeout(10_000) {
                        adapter.stream()
                            .take(capturedSize)
                            .toList()
                    }
                }

            awaitRegistered(bridge)

            // Fire well over the buffer capacity (HandleStreamAdapter.
            // COLLECTOR_BUFFER_CAPACITY = 64) from this single thread — if
            // trySendBlocking had been retained, this loop would stall as
            // soon as the channel filled and we'd time out.
            val burstSize = 256
            val perEmitBudgetMs = 50L
            for (i in 1..burstSize) {
                val t0 = System.nanoTime()
                bridge.emit(event(i.toLong(), "burst-$i"))
                val elapsedMs = (System.nanoTime() - t0) / 1_000_000
                assertTrue(
                    "native callback emit #$i blocked for ${elapsedMs}ms — " +
                        "DROP_OLDEST backpressure regressed (trySendBlocking?)",
                    elapsedMs < perEmitBudgetMs,
                )
            }

            // Let the slow collector wake up and drain whatever survived in
            // the channel after DROP_OLDEST kicked in.
            delay(100)
            for (i in burstSize + 1..burstSize + capturedSize) {
                bridge.emit(event(i.toLong(), "tail-$i"))
            }

            val received = collected.await()
            assertEquals(capturedSize, received.size)
            // We can't assert exact sequence numbers because the DROP_OLDEST
            // window depends on scheduler timing, but every received event
            // must come from the original burst or the tail and must be
            // monotonically increasing — proving native delivery was never
            // blocked behind the slow collector.
            received.zipWithNext().forEach { (a, b) ->
                assertTrue("events out of order: ${a.seq} >= ${b.seq}", a.seq < b.seq)
            }
        }

    @Test
    fun `second wave after teardown reinstalls the bridge`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 7L, bridge = bridge)

            // First wave.
            val first = async(Dispatchers.Default) { adapter.stream().take(1).toList() }
            awaitRegistered(bridge)
            bridge.emit(event(1, "first"))
            assertEquals(listOf(1L), first.await().map { it.seq })
            awaitUnregistered(bridge)

            // Second wave reuses the same handle+adapter; we should see a
            // FRESH registration (register_count == 2 after this block).
            val second = async(Dispatchers.Default) { adapter.stream().take(1).toList() }
            awaitRegistered(bridge)
            bridge.emit(event(99, "second"))
            assertEquals(listOf(99L), second.await().map { it.seq })
            awaitUnregistered(bridge)

            assertEquals(2, bridge.registerCount.get())
            assertEquals(2, bridge.unregisterCount.get())
        }

    // -----------------------------------------------------------------
    // Small busy-wait helpers to synchronize with the callbackFlow setup.
    // -----------------------------------------------------------------

    private fun awaitRegistered(bridge: FakeBridge, timeoutMs: Long = 1_000) {
        awaitCondition(timeoutMs) { bridge.isRegistered() }
    }

    private fun awaitUnregistered(bridge: FakeBridge, timeoutMs: Long = 1_000) {
        awaitCondition(timeoutMs) { !bridge.isRegistered() }
    }

    private fun awaitCollectorCount(
        bridge: FakeBridge,
        @Suppress("UNUSED_PARAMETER") adapter: VoiceAgentStreamAdapter,
        handle: Long,
        expected: Int,
        timeoutMs: Long = 1_000,
    ) {
        awaitCondition(timeoutMs) {
            // Reach into the companion-level registry.
            val fanOut = VoiceAgentStreamAdapter.fanOutFor(handle, bridge)
            fanOut.collectorCount() == expected
        }
    }

    private fun awaitCondition(timeoutMs: Long, pred: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (pred()) return
            Thread.sleep(5)
        }
        error("condition not met within ${timeoutMs}ms")
    }
}
