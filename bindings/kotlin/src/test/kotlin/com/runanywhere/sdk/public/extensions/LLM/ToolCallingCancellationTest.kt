/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions.LLM

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ToolCallingCancellationTest {
    @Test
    fun `cancellation hook fires before a blocked processing child completes`() =
        runBlocking {
            val ownerJob = Job()
            val scope = CoroutineScope(ownerJob + Dispatchers.Default)
            val hookHandle = CompletableDeferred<Long>()
            val hookCalls = AtomicInteger(0)
            val controller =
                RunLoopCancellationController { handle ->
                    hookCalls.incrementAndGet()
                    hookHandle.complete(handle)
                }
            controller.publishHandle(73L)

            val watcher = scope.launchRunLoopCancellationWatcher(ownerJob, controller)
            val processingStarted = CompletableDeferred<Unit>()
            val releaseProcessing = CompletableDeferred<Unit>()
            val processing =
                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                    try {
                        processingStarted.complete(Unit)
                        awaitCancellation()
                    } finally {
                        // Model a JNI call that remains blocked even after its
                        // coroutine has entered Cancelling.
                        withContext(NonCancellable) {
                            releaseProcessing.await()
                        }
                    }
                }

            try {
                processingStarted.await()
                ownerJob.cancel(CancellationException("deadline"))

                assertEquals(73L, withTimeout(1_000) { hookHandle.await() })
                assertFalse(
                    processing.isCompleted,
                    "native cancel must not wait for the blocked processing child",
                )
                assertEquals(1, hookCalls.get())
            } finally {
                releaseProcessing.complete(Unit)
                withContext(NonCancellable) {
                    processing.join()
                    watcher.join()
                }
            }
        }

    @Test
    fun `cancellation requested before handle publication dispatches when handle arrives`() =
        runBlocking {
            val ownerJob = Job()
            val scope = CoroutineScope(ownerJob + Dispatchers.Default)
            val hookHandle = CompletableDeferred<Long>()
            val hookCalls = AtomicInteger(0)
            val controller =
                RunLoopCancellationController { handle ->
                    hookCalls.incrementAndGet()
                    hookHandle.complete(handle)
                }
            val watcher = scope.launchRunLoopCancellationWatcher(ownerJob, controller)

            ownerJob.cancel(CancellationException("cancelled before native start"))
            withTimeout(1_000) { watcher.join() }
            assertFalse(hookHandle.isCompleted)

            controller.publishHandle(91L)
            assertEquals(91L, withTimeout(1_000) { hookHandle.await() })
            controller.publishHandle(92L)
            controller.requestCancellation()
            assertEquals(1, hookCalls.get())
        }

    @Test
    fun `parent cancellation unwinds suspended tool executor without orphan work`() =
        runBlocking {
            val ownerJob = Job()
            val executorStarted = CompletableDeferred<Unit>()
            val executorFinished = CompletableDeferred<Unit>()
            val bridgeFinished = CompletableDeferred<Unit>()
            val failure = AtomicReference<Throwable?>()
            val bridgeThread =
                Thread(
                    {
                        try {
                            runBlockingToolExecutor(ownerJob) {
                                executorStarted.complete(Unit)
                                try {
                                    awaitCancellation()
                                } finally {
                                    executorFinished.complete(Unit)
                                }
                            }
                        } catch (error: Throwable) {
                            failure.set(error)
                        } finally {
                            bridgeFinished.complete(Unit)
                        }
                    },
                    "tool-executor-test-bridge",
                )

            bridgeThread.start()
            try {
                withTimeout(1_000) { executorStarted.await() }
                ownerJob.cancel(CancellationException("generation timed out"))

                withTimeout(1_000) { executorFinished.await() }
                withTimeout(1_000) { bridgeFinished.await() }
                bridgeThread.join(1_000)

                assertFalse(bridgeThread.isAlive, "executor bridge escaped its owner Job")
                assertTrue(failure.get() is CancellationException)
            } finally {
                ownerJob.cancel()
                bridgeThread.join(1_000)
                if (bridgeThread.isAlive) bridgeThread.interrupt()
            }
        }

    @Test
    fun `linked tool executor preserves successful result`() {
        val ownerJob = Job()
        try {
            val result = runBlockingToolExecutor(ownerJob) { "completed" }

            assertEquals("completed", result)
            assertTrue(ownerJob.isActive)
        } finally {
            ownerJob.cancel()
        }
    }

    @Test
    fun `normal watcher teardown does not cancel native run loop`() =
        runBlocking {
            val ownerJob = Job()
            val hookCalls = AtomicInteger(0)
            val controller = RunLoopCancellationController { hookCalls.incrementAndGet() }
            controller.publishHandle(101L)
            val watcher =
                CoroutineScope(ownerJob + Dispatchers.Default)
                    .launchRunLoopCancellationWatcher(ownerJob, controller)

            watcher.cancelAndJoin()

            assertEquals(0, hookCalls.get())
            ownerJob.cancel()
        }
}
