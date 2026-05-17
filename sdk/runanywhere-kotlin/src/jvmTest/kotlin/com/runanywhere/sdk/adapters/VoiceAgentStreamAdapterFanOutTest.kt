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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
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
     * Slow-collector parity test (Swift `AsyncStream` / RN unbounded-queue
     * parity). The class doc for `HandleStreamAdapter` promises that the
     * C callback thread is never blocked by a slow collector. The buffer
     * policy is `Channel.UNLIMITED` (matches Swift's
     * `AsyncStream { ... }` default `.unbounded` and React Native's JS
     * array queue), so a slow collector:
     *
     *   1. NEVER stalls `bridge.emit(...)` (the simulated native
     *      callback thread) — `trySend` on an unlimited channel is
     *      non-blocking and lossless.
     *   2. ALWAYS observes every event eventually (no DROP_OLDEST) —
     *      every emitted event reaches the collector in producer order.
     */
    @Test
    fun `slow collector does not block native callback thread`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 123L, bridge = bridge)

            // Fire well over what would have been the old bounded buffer
            // (64). With UNLIMITED, each emit() returns promptly because
            // `trySend` on an unlimited channel is non-blocking — the
            // events accumulate in the channel, not in the producer.
            val burstSize = 256

            // Collector takes ALL burst events so it remains attached
            // for the duration of the producer loop. The "slow" property
            // we are validating is the non-blocking trySend on the
            // producer side; the consumer drains concurrently on
            // Dispatchers.Default but its pace is irrelevant — UNLIMITED
            // means the producer never waits for the consumer.
            val collected =
                async(Dispatchers.Default) {
                    withTimeout(10_000) {
                        adapter
                            .stream()
                            .take(burstSize)
                            .toList()
                    }
                }

            awaitRegistered(bridge)

            val perEmitBudgetMs = 50L
            for (i in 1..burstSize) {
                val t0 = System.nanoTime()
                bridge.emit(event(i.toLong(), "burst-$i"))
                val elapsedMs = (System.nanoTime() - t0) / 1_000_000
                assertTrue(
                    "native callback emit #$i blocked for ${elapsedMs}ms — " +
                        "trySend on Channel.UNLIMITED should never suspend",
                    elapsedMs < perEmitBudgetMs,
                )
            }

            val received = collected.await()
            assertEquals(burstSize, received.size)
            // Swift `AsyncStream` parity: every event is delivered
            // losslessly in order — no dropped suffix or shuffled window.
            assertEquals(
                "UNLIMITED buffer must deliver every event in producer order",
                (1L..burstSize.toLong()).toList(),
                received.map { it.seq },
            )
        }

    /**
     * Pass-2 syn-078 (a): cancelling one of N collectors mid-stream
     * does NOT tear down the shared C registration; the surviving
     * collector keeps receiving events with `registerCount == 1` and
     * `unregisterCount == 0` until the last collector detaches.
     *
     * The capture-then-release lock rewrite in `HandleStreamAdapter` is
     * specifically intended to make this transition safe.
     */
    @Test
    fun `cancelling one of two collectors mid-stream leaves the other receiving events`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 555L, bridge = bridge)

            val collectorScope = CoroutineScope(Dispatchers.Default)

            // Collector A — will be cancelled mid-stream.
            val receivedA = mutableListOf<Long>()
            val jobA =
                collectorScope.launch {
                    adapter.stream().collect { receivedA += it.seq }
                }

            // Collector B — keeps collecting through and past A's cancel.
            // Track partial progress in `receivedB` so the test can sync on
            // B having drained the pre-cancel burst before A is cancelled.
            val receivedB = java.util.Collections.synchronizedList(mutableListOf<Long>())
            val jobB =
                collectorScope.async {
                    val out = mutableListOf<Long>()
                    adapter
                        .stream()
                        .take(6)
                        .collect { ev ->
                            out += ev.seq
                            receivedB += ev.seq
                        }
                    out
                }

            awaitCollectorCount(bridge, adapter, handle = 555L, expected = 2)
            assertEquals(
                "exactly one native registration for two collectors",
                1,
                bridge.registerCount.get(),
            )

            // Pre-cancel burst: both collectors observe events 1..3.
            for (i in 1..3) bridge.emit(event(i.toLong(), "pre-$i"))

            // Wait until B has actually drained the pre-cancel burst before
            // cancelling A, otherwise A's cancellation may race with B's
            // dispatcher and the assertion below can briefly see fewer
            // than 3 events on B.
            awaitCondition(1_000) { receivedB.size >= 3 }

            // Cancel collector A.
            jobA.cancelAndJoin()
            awaitCollectorCount(bridge, adapter, handle = 555L, expected = 1)

            // Post-cancel events 4..6 must still reach B; the shared
            // registration is NOT torn down while B is still attached.
            assertEquals(
                "registration must survive A's cancel — still one register, no unregister",
                1 to 0,
                bridge.registerCount.get() to bridge.unregisterCount.get(),
            )

            for (i in 4..6) bridge.emit(event(i.toLong(), "post-$i"))

            val finalB = jobB.await()
            assertEquals(listOf(1L, 2L, 3L, 4L, 5L, 6L), finalB)

            // After B finishes via take(6), the registration is torn down
            // exactly once.
            awaitUnregistered(bridge)
            assertEquals(1, bridge.registerCount.get())
            assertEquals(1, bridge.unregisterCount.get())
        }

    /**
     * Pass-2 syn-078 (b): an event emitted AFTER one of N collectors
     * detaches still reaches the surviving collectors with the same
     * single registration (no spurious re-register, no unregister).
     */
    @Test
    fun `event emitted after partial detach still reaches surviving collector`() =
        runBlocking {
            val bridge = FakeBridge()
            val adapter = VoiceAgentStreamAdapter(handle = 777L, bridge = bridge)

            val collectorScope = CoroutineScope(Dispatchers.Default)

            val receivedA = java.util.Collections.synchronizedList(mutableListOf<Long>())
            val jobA =
                collectorScope.launch {
                    adapter.stream().collect { receivedA += it.seq }
                }

            val receivedB = java.util.Collections.synchronizedList(mutableListOf<Long>())
            val jobB =
                collectorScope.async {
                    val out = mutableListOf<Long>()
                    adapter
                        .stream()
                        .take(2)
                        .collect { ev ->
                            out += ev.seq
                            receivedB += ev.seq
                        }
                    out
                }

            awaitCollectorCount(bridge, adapter, handle = 777L, expected = 2)

            // First event — both collectors observe it.
            bridge.emit(event(1, "shared"))
            awaitCondition(1_000) { receivedA.size >= 1 && receivedB.size >= 1 }

            // Detach A.
            jobA.cancelAndJoin()
            awaitCollectorCount(bridge, adapter, handle = 777L, expected = 1)

            // Post-detach: registerCount is still 1, unregisterCount is still 0.
            assertEquals(
                "post-detach registration state must be (register=1, unregister=0)",
                1 to 0,
                bridge.registerCount.get() to bridge.unregisterCount.get(),
            )

            // Event emitted AFTER A's detach must still reach B (this is the
            // capture-then-release lock invariant the rewrite enforces).
            bridge.emit(event(2, "post-detach"))

            val finalB = jobB.await()
            assertEquals(listOf(1L, 2L), finalB)
            // A only saw the first event before it was cancelled.
            assertEquals(listOf(1L), receivedA.toList())

            awaitUnregistered(bridge)
            assertEquals(1, bridge.unregisterCount.get())
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
