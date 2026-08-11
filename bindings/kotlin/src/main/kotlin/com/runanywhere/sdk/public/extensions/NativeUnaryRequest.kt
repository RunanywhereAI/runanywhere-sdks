/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

private val nativeCancellationDispatcher = Dispatchers.IO.limitedParallelism(2)

/**
 * Runs a synchronous JNI request without losing coroutine cancellation.
 *
 * [coordinator] must be shared by every blocking request that targets the same
 * native service. Its request lease distinguishes queued work from the exact
 * request that currently owns that service. Cancelling queued or completed
 * work therefore cannot dispatch an unscoped native cancel into a different
 * request. Once admitted, cancellation invokes [cancel] before the owner waits
 * for the blocking worker to unwind. The worker is joined under
 * [NonCancellable], so a late native result can never escape to the caller.
 */
internal suspend fun <T> runCancellableNativeUnaryRequest(
    coordinator: NativeUnaryRequestCoordinator,
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    request: (requestId: Long) -> T,
    cancel: (requestId: Long) -> Unit,
): T =
    coroutineScope {
        val lease = coordinator.createLease(cancel)
        val worker =
            async(dispatcher) {
                lease.enter()
                try {
                    currentCoroutineContext().ensureActive()
                    if (!lease.tryStart()) {
                        throw CancellationException("Native request cancelled before entry")
                    }
                    request(lease.requestId)
                } finally {
                    lease.complete()
                }
            }

        try {
            worker.await()
        } catch (error: CancellationException) {
            coordinator.requestCancellation(lease)
            withContext(NonCancellable) { joinAll(worker) }
            throw error
        }
    }

/**
 * Serializes requests for one native service and scopes cancellation to the
 * lease that still owns it.
 *
 * The native VLM lifecycle and RAG session cancel ABIs identify only their
 * service/session, not an individual request. Keeping the old lease installed
 * until its blocking JNI call has returned closes the native-return/cleanup
 * gap: a successor cannot enter during that gap, and a late cancellation from
 * the predecessor is ignored after ownership has moved to the successor.
 * The JNI bridge receives [Lease.requestId] before entering the underlying
 * native operation. Its request relay retains pre-entry cancellation and
 * silently pulses an active request until that exact JNI wrapper completes,
 * closing the final Kotlin-to-native publication boundary without exposing a
 * cancellation to a successor.
 */
internal class NativeUnaryRequestCoordinator {
    private enum class LeaseState {
        QUEUED,
        ADMITTED,
        RUNNING,
        CANCELLED_BEFORE_ENTRY,
        CANCEL_DISPATCHED,
        COMPLETED,
    }

    private val gate = Mutex()
    private val lock = Any()
    private val nextRequestId = AtomicLong(1L)
    private var owner: Lease? = null

    internal fun createLease(cancel: (requestId: Long) -> Unit): Lease {
        val requestId = nextRequestId.getAndIncrement()
        check(requestId > 0L) { "Native request id space exhausted" }
        return Lease(requestId, cancel)
    }

    /**
     * Run a non-request operation under the same native-service gate.
     *
     * Lifecycle and state mutations use this path so they cannot replace or
     * destroy the native object while a request lease owns it. Set
     * [interruptActiveRequest] when the mutation should interrupt, rather
     * than merely wait for, the active request.
     */
    internal suspend fun <T> withExclusiveOperation(
        dispatcher: CoroutineDispatcher = Dispatchers.IO,
        interruptActiveRequest: Boolean = false,
        operation: () -> T,
    ): T =
        coroutineScope {
            val operationOwner = Any()
            // Enqueue the exclusive owner before cancelling the active
            // request. Once that request unwinds, a newly arriving request
            // cannot slip in and capture state that this mutation replaces.
            val worker =
                async(start = CoroutineStart.UNDISPATCHED) {
                    gate.lock(operationOwner)
                    try {
                        withContext(dispatcher) { operation() }
                    } finally {
                        gate.unlock(operationOwner)
                    }
                }
            if (interruptActiveRequest && !worker.isCompleted) {
                cancelActive()
            }
            worker.await()
        }

    /** Cancel the request that currently owns this native service, if any. */
    internal suspend fun cancelActive() {
        val active = synchronized(lock) { owner }
        if (active != null) {
            requestCancellation(active)
        }
    }

    /** Keep a potentially blocking JNI cancellation off the caller/Main thread. */
    internal suspend fun requestCancellation(lease: Lease) {
        withContext(NonCancellable + nativeCancellationDispatcher) {
            lease.requestCancellation()
        }
    }

    internal inner class Lease(
        internal val requestId: Long,
        private val cancel: (requestId: Long) -> Unit,
    ) {
        private var state = LeaseState.QUEUED

        suspend fun enter() {
            gate.lock(this)
            try {
                synchronized(lock) {
                    check(owner == null) { "Native unary service already has an owner" }
                    owner = this
                    state = LeaseState.ADMITTED
                }
            } catch (error: Throwable) {
                gate.unlock(this)
                throw error
            }
        }

        /**
         * Complete the cancellable admission handshake immediately before JNI.
         * Once this returns true, the blocking request is guaranteed to run
         * without another cancellation check, so every cancellation pulse
         * still belongs to this lease.
         */
        fun tryStart(): Boolean =
            synchronized(lock) {
                when (state) {
                    LeaseState.ADMITTED -> {
                        state = LeaseState.RUNNING
                        true
                    }
                    LeaseState.CANCELLED_BEFORE_ENTRY -> false
                    else -> false
                }
            }

        fun requestCancellation() {
            synchronized(lock) {
                if (owner === this) {
                    when (state) {
                        LeaseState.ADMITTED -> state = LeaseState.CANCELLED_BEFORE_ENTRY
                        LeaseState.RUNNING -> {
                            state = LeaseState.CANCEL_DISPATCHED
                            // The request-specific JNI relay blocks a stale
                            // completion transition while it delivers this
                            // cancel, and pulses silently if native admission
                            // has not happened yet.
                            runCatching { cancel(requestId) }
                        }
                        else -> Unit
                    }
                }
            }
        }

        fun complete() {
            synchronized(lock) {
                if (owner !== this) return
                owner = null
                state = LeaseState.COMPLETED
                gate.unlock(this)
            }
        }
    }
}
