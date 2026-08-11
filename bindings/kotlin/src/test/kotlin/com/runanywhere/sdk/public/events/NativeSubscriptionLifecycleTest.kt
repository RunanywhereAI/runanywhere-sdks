/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.events

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeSubscriptionLifecycleTest {
    @Test
    fun `stop waits for an in-flight start and retires its subscription`() {
        val subscribeEntered = CountDownLatch(1)
        val releaseSubscribe = CountDownLatch(1)
        val unsubscribed = Collections.synchronizedList(mutableListOf<Long>())
        val lifecycle =
            NativeSubscriptionLifecycle(
                subscribe = {
                    subscribeEntered.countDown()
                    assertTrue(releaseSubscribe.await(5, TimeUnit.SECONDS))
                    41L
                },
                unsubscribe = { unsubscribed += it },
            )

        val startThread = thread(start = true) { lifecycle.start() }
        assertTrue(subscribeEntered.await(5, TimeUnit.SECONDS))
        val stopThread = thread(start = true) { lifecycle.stop() }
        val blockedDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (stopThread.state != Thread.State.BLOCKED &&
            stopThread.isAlive &&
            System.nanoTime() < blockedDeadline
        ) {
            Thread.yield()
        }
        assertEquals(Thread.State.BLOCKED, stopThread.state)

        releaseSubscribe.countDown()
        startThread.join(5_000)
        stopThread.join(5_000)

        assertFalse(startThread.isAlive)
        assertFalse(stopThread.isAlive)
        assertEquals(listOf(41L), unsubscribed)
        assertFalse(lifecycle.stop())
    }

    @Test
    fun `stop wrapper propagates failure and retains ownership for retry`() {
        var unsubscribeAttempts = 0
        val lifecycle =
            NativeSubscriptionLifecycle(
                subscribe = { 73L },
                unsubscribe = {
                    unsubscribeAttempts += 1
                    if (unsubscribeAttempts == 1) error("synthetic teardown failure")
                },
            )

        assertTrue(lifecycle.start())
        assertFailsWith<IllegalStateException> { stopNativeSubscription(lifecycle) }
        assertFalse(lifecycle.start())
        assertTrue(stopNativeSubscription(lifecycle))
        assertEquals(2, unsubscribeAttempts)
    }

    @Test
    fun `linkage failure with a live subscription propagates for retry`() {
        var unsubscribeAttempts = 0
        val lifecycle =
            NativeSubscriptionLifecycle(
                subscribe = { 89L },
                unsubscribe = {
                    unsubscribeAttempts += 1
                    if (unsubscribeAttempts == 1) {
                        throw UnsatisfiedLinkError("synthetic missing JNI symbol")
                    }
                },
            )

        assertTrue(lifecycle.start())
        assertFailsWith<UnsatisfiedLinkError> { stopNativeSubscription(lifecycle) }
        assertFalse(lifecycle.start())
        assertTrue(stopNativeSubscription(lifecycle))
        assertEquals(2, unsubscribeAttempts)
    }
}
