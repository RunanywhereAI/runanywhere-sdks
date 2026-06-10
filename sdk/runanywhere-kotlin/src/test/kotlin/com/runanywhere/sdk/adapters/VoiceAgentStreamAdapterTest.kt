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
 * Uses the test-only `NativeBridge` SPI seam so no JNI symbol is required.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.SessionStartedEvent
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
                        received += it.session_started?.session_id ?: "<no-id>"
                    }
                }

            val installed = waitFor { bridge.registerCount.get() == 1 }
            assertTrue("register must run for first subscriber", installed)

            val cb = bridge.capturedCallback.get()!!
            cb(VoiceEvent(session_started = SessionStartedEvent(session_id = "s1")).encode())
            cb(VoiceEvent(session_started = SessionStartedEvent(session_id = "s2")).encode())

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

            val jobA =
                launch(Dispatchers.Default) {
                    adapter.stream().take(1).collect { a += it.session_started?.session_id ?: "" }
                }
            val jobB =
                launch(Dispatchers.Default) {
                    adapter.stream().take(1).collect { b += it.session_started?.session_id ?: "" }
                }

            val ready =
                waitFor {
                    bridge.registerCount.get() == 1 && bridge.capturedCallback.get() != null
                }
            assertTrue("single C registration must service both collectors", ready)

            bridge.capturedCallback
                .get()!!
                .invoke(VoiceEvent(session_started = SessionStartedEvent(session_id = "shared")).encode())

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

            val jobs: MutableList<Job> = mutableListOf()
            for (i in 0 until 3) {
                jobs += launch(Dispatchers.Default) { adapter.stream().collect { } }
            }

            val installed = waitFor { bridge.registerCount.get() == 1 }
            assertTrue("register must run once for the cohort", installed)
            assertEquals("no teardown before any detach", 0, bridge.unregisterCount.get())

            for (j in jobs) j.cancel()
            for (j in jobs) j.join()

            val torn = waitFor { bridge.unregisterCount.get() == 1 }
            assertTrue("unregister must fire exactly once after last detach", torn)
            assertEquals(1, bridge.unregisterCount.get().toLong())
        }
}
