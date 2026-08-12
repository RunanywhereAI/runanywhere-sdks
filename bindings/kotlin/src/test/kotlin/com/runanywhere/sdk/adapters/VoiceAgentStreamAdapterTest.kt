/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Coverage for the `VoiceAgentStreamAdapter` thin wrapper over the generic
 * `HandleStreamAdapter`. Tests verify the specialization wires the bridge's
 * `registerCallback` / `unregisterCallback` symbols, fans events out to
 * multiple collectors, and tears down lazily on last-detach (mirrors Swift
 * `VoiceAgentStreamAdapter`'s no-terminal-event semantics).
 *
 * `VoiceEvent.session_started`/`SessionStartedEvent` are deleted outright
 * (idl/voice_events.proto): session identity now lives on the envelope's own
 * top-level `session_id` field, carried alongside any payload arm (here
 * `user_said`), rather than a dedicated session-started oneof arm.
 *
 * Uses the test-only `NativeBridge` SPI seam so no JNI symbol is required.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.UserSaidEvent
import ai.runanywhere.proto.v1.VoiceEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

@OptIn(ExperimentalCoroutinesApi::class)
class VoiceAgentStreamAdapterTest {
    /** In-process fake bridge that captures the registered callback so tests
     *  can drive proto-byte payloads through the same path the JNI trampoline
     *  would use in production. */
    private class FakeBridge : VoiceAgentStreamAdapter.NativeBridge {
        val registerCount = AtomicInteger(0)
        val unregisterCount = AtomicInteger(0)
        val quiesceCount = AtomicInteger(0)
        val capturedCallback = AtomicReference<((ByteArray) -> Unit)?>(null)
        var nextCallbackId: Long = 1L

        override fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long {
            registerCount.incrementAndGet()
            capturedCallback.set(cb)
            return nextCallbackId
        }

        override fun unregisterCallback(handle: Long, callbackId: Long) {
            unregisterCount.incrementAndGet()
            capturedCallback.set(null)
        }

        override fun quiesce() {
            quiesceCount.incrementAndGet()
        }
    }

    private suspend fun waitFor(timeoutMs: Long = 1500, predicate: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return true
            delay(10)
        }
        return predicate()
    }

    @Test
    fun `single subscriber sees decoded voice events`() =
        runBlocking {
            val bridge = FakeBridge()
            val handle: Long = 0xA1L
            val adapter = VoiceAgentStreamAdapter(handle, bridge)
            val received = mutableListOf<String>()

            val job =
                launch(Dispatchers.Default) {
                    adapter.stream().take(2).collect {
                        received += it.session_id.ifEmpty { "<no-id>" }
                    }
                }

            val installed = waitFor { bridge.registerCount.get() == 1 }
            assertTrue("register must run for first subscriber", installed)

            val cb = bridge.capturedCallback.get()!!
            cb(VoiceEvent(session_id = "s1", user_said = UserSaidEvent(text = "hi")).encode())
            cb(VoiceEvent(session_id = "s2", user_said = UserSaidEvent(text = "hi again")).encode())

            job.join()
            assertEquals(listOf("s1", "s2"), received)
        }

    @Test
    fun `multiple collectors share one C registration and each gets the event`() =
        runBlocking {
            val bridge = FakeBridge()
            val handle: Long = 0xB2L
            val adapter = VoiceAgentStreamAdapter(handle, bridge)
            val a = mutableListOf<String>()
            val b = mutableListOf<String>()
            val seenA = AtomicInteger(0)
            val seenB = AtomicInteger(0)

            val jobA =
                launch(Dispatchers.Default) {
                    adapter.stream().take(1).collect {
                        a += it.session_id
                        seenA.incrementAndGet()
                    }
                }
            val jobB =
                launch(Dispatchers.Default) {
                    adapter.stream().take(1).collect {
                        b += it.session_id
                        seenB.incrementAndGet()
                    }
                }

            val ready =
                waitFor {
                    bridge.registerCount.get() == 1 && bridge.capturedCallback.get() != null
                }
            assertTrue("single C registration must service both collectors", ready)

            // Drive the event until BOTH collectors have observed one, exactly
            // as `last detach tears down the C registration` does below and for
            // the same reason: registerCount hits 1 the instant the FIRST
            // collector attaches, so firing a single event there races jobB's
            // attach. Losing that race left jobB's take(1) waiting on an event
            // that had already been broadcast, jobB.join() blocked forever, and
            // :testDebugUnitTest hung with no output until the CI job's 6 h
            // ceiling. take(1) completes and detaches a collector the moment it
            // receives, so a re-invoke only ever reaches one that has not been
            // served yet — each still ends with exactly one event, and the
            // assertions below are unchanged.
            val bothServed =
                waitFor(timeoutMs = 3000) {
                    bridge.capturedCallback
                        .get()
                        ?.invoke(VoiceEvent(session_id = "shared", user_said = UserSaidEvent(text = "hi")).encode())
                    seenA.get() > 0 && seenB.get() > 0
                }
            assertTrue("both collectors must be served by the one registration", bothServed)

            jobA.join()
            jobB.join()
            assertEquals(listOf("shared"), a)
            assertEquals(listOf("shared"), b)
            assertEquals(
                "two collectors must NOT each install a fresh C registration",
                1,
                bridge.registerCount.get(),
            )
        }

    @Test
    fun `last detach tears down the C registration`() =
        runBlocking {
            val bridge = FakeBridge()
            val handle: Long = 0xC3L
            val adapter = VoiceAgentStreamAdapter(handle, bridge)

            // Per-collector observed-event counters. Waiting only on
            // registerCount==1 is not enough: that fires as soon as the FIRST
            // collector attaches, so cancelling then can race a late attacher
            // into a SECOND cohort (register/unregister twice). We instead
            // confirm all three share the one registration before detaching.
            val seen = List(3) { AtomicInteger(0) }
            val jobs: MutableList<Job> = mutableListOf()
            for (i in 0 until 3) {
                jobs += launch(Dispatchers.Default) { adapter.stream().collect { seen[i].incrementAndGet() } }
            }

            val installed =
                waitFor { bridge.registerCount.get() == 1 && bridge.capturedCallback.get() != null }
            assertTrue("register must run once for the cohort", installed)
            assertEquals("no teardown before any detach", 0, bridge.unregisterCount.get())

            // Drive events until every collector observes one: proof that all
            // three attached to the SAME registration before we tear down.
            val cohortReady =
                waitFor(timeoutMs = 3000) {
                    bridge.capturedCallback
                        .get()
                        ?.invoke(VoiceEvent(session_id = "warmup", user_said = UserSaidEvent(text = "x")).encode())
                    seen.all { it.get() > 0 }
                }
            assertTrue("all three collectors must attach to the same registration", cohortReady)
            assertEquals("cohort shares exactly one registration", 1, bridge.registerCount.get())

            for (j in jobs) j.cancel()
            for (j in jobs) j.join()

            val torn = waitFor { bridge.unregisterCount.get() == 1 }
            assertTrue("unregister must fire exactly once after last detach", torn)
            assertEquals(1, bridge.unregisterCount.get().toLong())
            assertEquals(1, bridge.quiesceCount.get().toLong())
        }
}
