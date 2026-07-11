/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.withContext

/**
 * Runs a synchronous JNI request without losing coroutine cancellation.
 *
 * The small admission gate distinguishes a request that has merely been
 * queued from one that is guaranteed to enter [request]. Cancelling a queued
 * request therefore does not leave a native cancel latched for some later,
 * unrelated request. Once admitted, cancellation invokes [cancel] before the
 * owner waits for the blocking worker to unwind. The worker is joined under
 * [NonCancellable], so a late native result can never escape to the caller.
 */
internal suspend fun <T> runCancellableNativeUnaryRequest(
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    request: () -> T,
    cancel: () -> Unit,
): T = coroutineScope {
    val admission = NativeUnaryRequestAdmission(cancel)
    val worker =
        async(dispatcher) {
            if (!admission.tryEnter()) {
                throw CancellationException("Native request cancelled before entry")
            }
            try {
                request()
            } finally {
                admission.complete()
            }
        }

    try {
        worker.await()
    } catch (error: CancellationException) {
        admission.requestCancellation()
        withContext(NonCancellable) { joinAll(worker) }
        throw error
    }
}

private class NativeUnaryRequestAdmission(
    private val cancel: () -> Unit,
) {
    private enum class State {
        QUEUED,
        ENTERED,
        CANCELLED_BEFORE_ENTRY,
        CANCEL_DISPATCHED,
        COMPLETED,
    }

    private val lock = Any()
    private var state = State.QUEUED

    fun tryEnter(): Boolean =
        synchronized(lock) {
            when (state) {
                State.QUEUED -> {
                    state = State.ENTERED
                    true
                }
                State.CANCELLED_BEFORE_ENTRY -> false
                else -> false
            }
        }

    fun requestCancellation() {
        synchronized(lock) {
            when (state) {
                State.QUEUED -> state = State.CANCELLED_BEFORE_ENTRY
                State.ENTERED -> {
                    state = State.CANCEL_DISPATCHED
                    // Native cancellation is deliberately issued while the
                    // completion transition is excluded. This prevents a
                    // just-finished request from receiving an idle/stale
                    // cancel after its replacement has started.
                    runCatching(cancel)
                }
                else -> Unit
            }
        }
    }

    fun complete() {
        synchronized(lock) {
            state = State.COMPLETED
        }
    }
}
