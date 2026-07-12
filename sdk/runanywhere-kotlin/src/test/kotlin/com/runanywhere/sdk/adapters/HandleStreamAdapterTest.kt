/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Adapter coverage for the `HandleStreamAdapter` fan-out machine. Ports the
 * Swift reference suite `HandleStreamAdapterTests.swift`:
 *   1. Flow cancellation triggers exactly one C-side teardown.
 *   2. N concurrent first-subscribers collapse to a single install.
 *   3. install() failure rolls back every pending continuation and resets
 *      the state machine so a retry re-enters register().
 *   4. Distinct handles with colliding hashes stay independent (per-handle
 *      isolation in the static fan-out registry).
 *   5. Cancel-to-native latency contract (<250 ms cross-SDK budget).
 *
 * The tests inject synthetic `register` / `unregister` closures rather than
 * touching the real JNI, so they assert lifecycle invariants without dlsym-
 * resolving any `rac_*_set_stream_proto_callback` symbol.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.ChatMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

@OptIn(ExperimentalCoroutinesApi::class)
class HandleStreamAdapterTest {
    /** UUID-keyed handle so each test gets a unique static-registry bucket. */
    private data class UniqueHandle(
        val id: String =
            java.util.UUID
                .randomUUID()
                .toString(),
    )

    /** Handle whose `hashCode()` collapses to a constant so two distinct
     *  instances necessarily share `hashCode`. Used by the hash-collision
     *  isolation test to force `equals`-based disambiguation. */
    private data class CollidingHandle(
        val id: Int,
    ) {
        override fun hashCode(): Int = 0
    }

    private fun uniqueStreamKey(prefix: String = "test"): String =
        "$prefix-${java.util.UUID.randomUUID()}"

    /** Poll [predicate] at 10ms intervals up to [timeoutMs]. */
    private suspend fun waitFor(timeoutMs: Long = 2000, predicate: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return true
            delay(10)
        }
        return predicate()
    }

    // MARK: - Test 1: Flow cancellation triggers exactly one teardown

    @Test
    fun `flow cancellation terminates native work`() =
        runBlocking {
            val registerCount = AtomicInteger(0)
            val unregisterCount = AtomicInteger(0)
            val quiesceCount = AtomicInteger(0)
            val handle = UniqueHandle()
            val streamKey = uniqueStreamKey()

            val adapter =
                HandleStreamAdapter<UniqueHandle, ChatMessage>(
                    handle = handle,
                    streamKey = streamKey,
                    register = { _, _ ->
                        registerCount.incrementAndGet()
                        // Return a non-zero id so attach() proceeds.
                        42L
                    },
                    unregister = { _, _ ->
                        unregisterCount.incrementAndGet()
                    },
                    quiesce = { quiesceCount.incrementAndGet() },
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )

            val consumer =
                launch(Dispatchers.Default) {
                    adapter.stream().collect { /* no events delivered; we cancel below */ }
                }

            val installed = waitFor { registerCount.get() == 1 }
            assertTrue("register must run exactly once for the first subscriber", installed)

            consumer.cancel()
            consumer.join()

            val torn = waitFor { unregisterCount.get() == 1 }
            assertTrue("unregister must fire exactly once when the sole subscriber cancels", torn)
            assertEquals("quiesce must follow native unregister", 1, quiesceCount.get())
            assertEquals("teardown must not re-enter register()", 1, registerCount.get())
        }

    // MARK: - Test 2: Concurrent first-subscribers collapse to a single install

    @Test
    fun `concurrent first subscribers serialize install`() =
        runBlocking {
            val registerCount = AtomicInteger(0)
            val unregisterCount = AtomicInteger(0)
            val handle = UniqueHandle()
            val streamKey = uniqueStreamKey()

            val adapter =
                HandleStreamAdapter<UniqueHandle, ChatMessage>(
                    handle = handle,
                    streamKey = streamKey,
                    register = { _, _ ->
                        registerCount.incrementAndGet()
                        // Widen the install window so concurrent attaches race
                        // through and observe INSTALLING. Blocking the
                        // dispatcher is acceptable here — only the installer
                        // ever enters this branch.
                        Thread.sleep(50)
                        99L
                    },
                    unregister = { _, _ ->
                        unregisterCount.incrementAndGet()
                    },
                    quiesce = {},
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )

            val consumerCount = 10
            val consumers: MutableList<Job> = mutableListOf()
            for (i in 0 until consumerCount) {
                consumers +=
                    launch(Dispatchers.Default) {
                        adapter.stream().collect { /* never delivered */ }
                    }
            }

            // Wait long enough for all 10 attaches to land and the installer's
            // 50ms blocking register() to complete.
            delay(250)
            assertEquals(
                "register must run exactly once even with $consumerCount concurrent attaches",
                1,
                registerCount.get(),
            )

            for (c in consumers) c.cancel()
            for (c in consumers) c.join()

            val torn = waitFor { unregisterCount.get() == 1 }
            assertTrue("unregister must fire exactly once after the last subscriber detaches", torn)
            assertEquals(1, unregisterCount.get().toLong())
        }

    // MARK: - Test 3: install failure rolls back every pending continuation

    @Test
    fun `install failure rolls back and resets state`() =
        runBlocking {
            val registerCount = AtomicInteger(0)
            val unregisterCount = AtomicInteger(0)
            val failuresRemaining = AtomicInteger(1)
            val handle = UniqueHandle()
            val streamKey = uniqueStreamKey()

            val adapter =
                HandleStreamAdapter<UniqueHandle, ChatMessage>(
                    handle = handle,
                    streamKey = streamKey,
                    register = { _, _ ->
                        registerCount.incrementAndGet()
                        val shouldFail = failuresRemaining.getAndUpdate { if (it > 0) it - 1 else it } > 0
                        // INVALID_CALLBACK_ID (0) signals failure; non-zero is success.
                        if (shouldFail) HandleStreamAdapter.INVALID_CALLBACK_ID else 7L
                    },
                    unregister = { _, _ ->
                        unregisterCount.incrementAndGet()
                    },
                    quiesce = {},
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )

            // Drive the failing install; the for-await must drain to zero
            // because the rollback closes the channel.
            val received = adapter.stream().toList()
            assertEquals("failed install must not deliver any events", 0, received.size)
            assertEquals("register must run exactly once on first install attempt", 1, registerCount.get())
            assertEquals(
                "unregister must NOT fire when install never reached INSTALLED",
                0,
                unregisterCount.get(),
            )

            // A second subscriber must reach register() — proving the state
            // machine rolled back to NOT_INSTALLED.
            val secondConsumer =
                launch(Dispatchers.Default) {
                    adapter.stream().collect { /* never delivered */ }
                }
            val retried = waitFor { registerCount.get() == 2 }
            assertTrue("state machine must reset so a retry re-enters register()", retried)

            secondConsumer.cancel()
            secondConsumer.join()
            val torn = waitFor { unregisterCount.get() == 1 }
            assertTrue("successful install + cancel must fire unregister exactly once", torn)
        }

    // MARK: - Test 4: Distinct handles with colliding hashes stay independent

    @Test
    fun `handle hash collision does not alias streams`() =
        runBlocking {
            val streamKey = uniqueStreamKey()
            val handleA = CollidingHandle(id = 1)
            val handleB = CollidingHandle(id = 2)

            assertEquals(
                "test prereq: handles must hash equally",
                handleA.hashCode(),
                handleB.hashCode(),
            )
            assertNotEquals("test prereq: handles must compare distinct under equals", handleA, handleB)

            val cbA = arrayOfNulls<((ByteArray) -> Unit)>(1)
            val cbB = arrayOfNulls<((ByteArray) -> Unit)>(1)

            val adapterA =
                HandleStreamAdapter<CollidingHandle, ChatMessage>(
                    handle = handleA,
                    streamKey = streamKey,
                    register = { _, cb ->
                        cbA[0] = cb
                        1L
                    },
                    unregister = { _, _ -> },
                    quiesce = {},
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )
            val adapterB =
                HandleStreamAdapter<CollidingHandle, ChatMessage>(
                    handle = handleB,
                    streamKey = streamKey,
                    register = { _, cb ->
                        cbB[0] = cb
                        2L
                    },
                    unregister = { _, _ -> },
                    quiesce = {},
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )

            val receivedA = mutableListOf<String>()
            val receivedB = mutableListOf<String>()

            val jobA =
                launch(Dispatchers.Default) {
                    adapterA.stream().take(1).collect { receivedA += it.id }
                }
            val jobB =
                launch(Dispatchers.Default) {
                    adapterB.stream().take(1).collect { receivedB += it.id }
                }

            val ready = waitFor { cbA[0] != null && cbB[0] != null }
            assertTrue("both fan-out registrations must capture their trampolines", ready)

            cbA[0]!!.invoke(ChatMessage(id = "from-A").encode())
            cbB[0]!!.invoke(ChatMessage(id = "from-B").encode())

            jobA.join()
            jobB.join()

            assertEquals(
                "handleA's stream must receive only handleA's event",
                listOf("from-A"),
                receivedA,
            )
            assertEquals(
                "handleB's stream must receive only handleB's event",
                listOf("from-B"),
                receivedB,
            )
        }

    // MARK: - Test 5: Cross-SDK cancel-to-native latency contract

    @Test
    fun `cancel to native latency is bounded`() =
        runBlocking {
            val registerCount = AtomicInteger(0)
            val unregisterCount = AtomicInteger(0)
            val handle = UniqueHandle()
            val streamKey = uniqueStreamKey()

            val adapter =
                HandleStreamAdapter<UniqueHandle, ChatMessage>(
                    handle = handle,
                    streamKey = streamKey,
                    register = { _, _ ->
                        registerCount.incrementAndGet()
                        13L
                    },
                    unregister = { _, _ ->
                        unregisterCount.incrementAndGet()
                    },
                    quiesce = {},
                    decodeEvent = { ChatMessage.ADAPTER.decode(it) },
                    isTerminalEvent = null,
                )

            val consumerCount = 5
            val consumers: MutableList<Job> = mutableListOf()
            for (i in 0 until consumerCount) {
                consumers += launch(Dispatchers.Default) { adapter.stream().collect { } }
            }

            val installed = waitFor { registerCount.get() == 1 }
            assertTrue("register must run exactly once for the consumer cohort", installed)

            val start = System.currentTimeMillis()
            for (c in consumers) c.cancel()
            for (c in consumers) c.join()

            val torn =
                withTimeoutOrNull(250) {
                    waitFor { unregisterCount.get() == 1 }
                } ?: false
            val elapsed = System.currentTimeMillis() - start
            assertTrue(
                "cross-SDK cancel-to-native latency contract violated: ${elapsed}ms > 250ms",
                torn,
            )
            assertTrue(
                "cancel-to-native unregister fired in ${elapsed}ms (budget 250ms)",
                elapsed < 250,
            )
            assertEquals(
                "unregister must fire exactly once regardless of how many consumers cancel",
                1,
                unregisterCount.get(),
            )
            assertEquals("teardown must not re-enter register()", 1, registerCount.get())
        }
}
