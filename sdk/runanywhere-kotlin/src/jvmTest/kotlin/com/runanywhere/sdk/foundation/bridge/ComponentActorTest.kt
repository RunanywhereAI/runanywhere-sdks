/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ComponentActorTest.kt
 *
 * Pass-2 syn-076 direct coverage for the new component-lifecycle critical
 * section. The actor was extracted in W2 to keep
 * `getOrCreateHandle + nativeLoad + loadedAssetId update` inside one
 * coroutine-Mutex critical section, mirroring Swift's `actor` isolation.
 *
 * These tests exercise the critical section without the JNI layer by
 * passing a fake [ComponentVTable] backed by atomic counters and a
 * latch-controlled load function. They cover:
 *
 *   (a) `loadModel` atomically owns `create + load + assetId`: a second
 *       concurrent `loadModel` cannot observe `loadedAssetId` set by an
 *       in-flight load.
 *   (b) `destroy()` during an in-flight `loadModel` awaits the load
 *       before tearing the handle down.
 *   (c) `currentAssetId` is `null` until `loadModel` returns and is
 *       cleared on `destroy()`.
 *   (d) The native `create` is invoked at most once per actor instance
 *       even under concurrent `loadModel`/`getHandle` calls.
 */

package com.runanywhere.sdk.foundation.bridge

import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ComponentActorTest {
    /**
     * Build a [ComponentVTable] whose `create` returns a synthetic handle
     * and whose `loadModel` slot blocks on a caller-supplied gate. The
     * gate lets tests choreograph concurrent `loadModel` calls.
     */
    private class FakeVTable(
        val createCount: AtomicInteger = AtomicInteger(0),
        val destroyCount: AtomicInteger = AtomicInteger(0),
        val cleanupCount: AtomicInteger = AtomicInteger(0),
        val loadCount: AtomicInteger = AtomicInteger(0),
        private val handleSupplier: () -> Long = { 0x1234ABCDL },
        private val loadGate: (() -> Unit)? = null,
    ) {
        fun toVTable(): ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_LLM,
                createFn = {
                    createCount.incrementAndGet()
                    handleSupplier()
                },
                destroyFn = { destroyCount.incrementAndGet() },
                loadModel = { _, _, _, _ ->
                    loadCount.incrementAndGet()
                    loadGate?.invoke()
                    0 // RAC_SUCCESS
                },
            )
    }

    /**
     * Test (c): `currentAssetId` is `null` before `loadModel` returns,
     * and the value supplied to `loadModel` is published exactly once
     * after the load completes. `destroy()` clears it.
     */
    @Test
    fun `loadModel publishes assetId atomically and destroy clears it`() =
        runBlocking {
            val fake = FakeVTable()
            val actor = ComponentActor(fake.toVTable())

            assertNull("assetId is null before any load", actor.currentAssetId)

            actor.loadModel(path = "/tmp/foo.gguf", id = "test-model", name = "Test")
            assertEquals("test-model", actor.currentAssetId)
            assertEquals("create runs exactly once", 1, fake.createCount.get())
            assertEquals("load runs exactly once", 1, fake.loadCount.get())

            actor.destroy()
            assertNull("assetId cleared on destroy", actor.currentAssetId)
            assertTrue(actor.isShutDown)
            assertEquals("native destroy invoked once", 1, fake.destroyCount.get())
        }

    /**
     * Test (a) + (d): concurrent `loadModel` calls serialize through the
     * actor's Mutex. The native `create` runs exactly once across the
     * burst, and each `loadModel` invocation runs to completion before
     * the next observes the actor state.
     */
    @Test
    fun `concurrent loadModel calls serialize through the actor mutex`() =
        runBlocking {
            val fake = FakeVTable()
            val actor = ComponentActor(fake.toVTable())

            val ids = (1..16).map { "model-$it" }
            withTimeout(5_000) {
                ids
                    .map { id ->
                        async(Dispatchers.Default) {
                            actor.loadModel(path = "/tmp/$id", id = id, name = id)
                        }
                    }.awaitAll()
            }

            assertEquals(
                "native create must run exactly once across N concurrent loadModel calls",
                1,
                fake.createCount.get(),
            )
            assertEquals(
                "every loadModel call must trigger exactly one native load",
                ids.size,
                fake.loadCount.get(),
            )
            // The last-winner asset id is non-null and is one of the requested ids.
            val winner = actor.currentAssetId
            assertTrue("currentAssetId must be one of the requested ids", winner in ids)
        }

    /**
     * Test (b): `destroy()` does not interleave with an in-flight
     * `loadModel`. With the Mutex, `destroy()` must wait for the load
     * to release the lock before tearing the handle down — the test
     * asserts that the destroy callback is observed AFTER the load
     * callback completes.
     */
    @Test
    fun `destroy during in-flight loadModel awaits load completion`() =
        runBlocking {
            val loadStarted = CompletableDeferred<Unit>()
            val releaseLoad = CompletableDeferred<Unit>()
            val orderLog = mutableListOf<String>()
            val orderLock = Any()

            fun log(event: String) = synchronized(orderLock) { orderLog += event }

            val fake =
                FakeVTable(
                    loadGate = {
                        log("load:start")
                        loadStarted.complete(Unit)
                        // Block the load until the test releases it. The block
                        // runs synchronously inside `vtable.loadModel(...)`,
                        // which is invoked under the actor's Mutex.
                        runBlocking { releaseLoad.await() }
                        log("load:end")
                    },
                )

            // Wire destroy to log so we can assert ordering.
            val baseVTable = fake.toVTable()
            val tracedVTable =
                ComponentVTable(
                    component = SDKComponent.SDK_COMPONENT_LLM,
                    createFn = { baseVTable.create() },
                    destroyFn = { h ->
                        log("destroy:start")
                        baseVTable.destroy(h)
                        log("destroy:end")
                    },
                    loadModel = { h, p, i, n -> baseVTable.loadModel!!(h, p, i, n) },
                )

            val actor = ComponentActor(tracedVTable)

            val loadJob =
                launch(Dispatchers.Default) {
                    actor.loadModel(path = "/tmp/m", id = "m", name = "m")
                }

            // Wait until the load is in flight, then issue destroy.
            withTimeout(2_000) { loadStarted.await() }

            val destroyJob =
                launch(Dispatchers.Default) {
                    actor.destroy()
                }

            // Give destroy a moment to attempt acquiring the Mutex; it
            // must block until we release the load.
            repeat(20) {
                yield()
                delay(5)
            }
            synchronized(orderLock) {
                assertFalse(
                    "destroy must NOT run while loadModel still holds the actor Mutex",
                    orderLog.contains("destroy:start"),
                )
            }

            releaseLoad.complete(Unit)
            withTimeout(2_000) {
                loadJob.join()
                destroyJob.join()
            }

            // Order: load:start -> load:end -> destroy:start -> destroy:end.
            val snapshot = synchronized(orderLock) { orderLog.toList() }
            val loadEndIdx = snapshot.indexOf("load:end")
            val destroyStartIdx = snapshot.indexOf("destroy:start")
            if (loadEndIdx < 0 || destroyStartIdx < 0) {
                fail("expected load:end and destroy:start in trace; saw=$snapshot")
            }
            assertTrue(
                "destroy:start must follow load:end, but trace was $snapshot",
                destroyStartIdx > loadEndIdx,
            )

            assertTrue(actor.isShutDown)
            assertNull(actor.currentAssetId)
        }

    /**
     * `getHandle` lazily creates the handle and shares it across callers;
     * subsequent calls do not re-create.
     */
    @Test
    fun `getHandle creates lazily and is shared across callers`() =
        runBlocking {
            val fake = FakeVTable()
            val actor = ComponentActor(fake.toVTable())

            val first = actor.getHandle()
            val second = actor.getHandle()
            assertEquals(first, second)
            assertEquals("create runs exactly once for repeated getHandle", 1, fake.createCount.get())
        }

    /**
     * After `destroy()`, further `getHandle` calls throw rather than
     * silently recreating the handle.
     */
    @Test
    fun `getHandle after destroy throws notInitialized`() =
        runBlocking {
            val fake = FakeVTable()
            val actor = ComponentActor(fake.toVTable())
            actor.destroy()

            try {
                actor.getHandle()
                fail("expected SDKException for post-destroy getHandle")
            } catch (e: SDKException) {
                // Expected — actor is shut down.
                assertTrue(e.message?.contains("shut down") == true)
            }
        }
}
