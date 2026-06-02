/*
 * HandleStreamAdapter.kt
 *
 * Kotlin port of Swift's `Sources/RunAnywhere/Adapters/HandleStreamAdapter.swift`.
 *
 * Generic `Flow`-based wrapper over a proto-byte streaming C ABI of the
 * shape `(handle, callback, userData) -> int`. Replaces the duplicated
 * fan-out machinery that would otherwise repeat across LLMStreamAdapter
 * and VoiceAgentStreamAdapter (and any future per-handle stream).
 *
 * The C ABI exposes a SINGLE proto-callback slot per handle, so a naive
 * adapter would silently let one collector clobber another. This generic
 * installs ONE C-side registration lazily on the first subscriber and
 * tears it down when the last subscriber detaches, fanning each decoded
 * event out to every active `Flow` collector.
 *
 * Semantics (matched to Swift's HandleStreamAdapter exactly):
 *   * The first subscriber installs one C callback registration.
 *   * Subsequent subscribers fan out from the same registration — all
 *     share the single registered trampoline.
 *   * On the last subscriber unsubscribing the registration is torn
 *     down and the per-handle fan-out is removed from the static map.
 *   * If the caller supplies `isTerminalEvent`, an event satisfying
 *     the predicate finishes every collector and tears down the
 *     registration immediately (the LLM `is_final` semantics). When the
 *     predicate is omitted (the VoiceAgent case) events fan out
 *     forever until consumers detach.
 *
 * Concurrency:
 *   * Per-handle state is guarded by `synchronized(lock)`. State ops
 *     happen inside both suspend (collector attach/detach) and
 *     non-suspend (C callback trampoline) contexts, so a coroutine
 *     `Mutex` cannot be used uniformly.
 *   * The per-handle registry is a `MutableMap` guarded by its own
 *     monitor — KMP commonMain has no `ConcurrentHashMap`, but the
 *     critical sections are O(1) and contention is low.
 *
 * Public API:
 *     val adapter = HandleStreamAdapter<Long, LLMStreamEvent>(
 *         handle = handle,
 *         streamKey = "llm",
 *         register = { h, cb -> bridge.registerCallback(h, cb) },
 *         unregister = { h, id -> bridge.unregisterCallback(h, id) },
 *         decodeEvent = { bytes -> LLMStreamEvent.ADAPTER.decode(bytes) },
 *         isTerminalEvent = { it.is_final },
 *     )
 *     adapter.stream().collect { event -> ... }
 *
 * Cancellation: standard `Flow` cancellation (collector cancelled,
 * `take(N)` completes, etc.) fires `awaitClose`, which detaches the
 * channel. When the last channel detaches the C registration is torn
 * down.
 */

package com.runanywhere.sdk.adapters

import com.squareup.wire.Message
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow

/**
 * Generic Flow wrapper for proto-byte streaming C ABIs that follow the
 * `(handle, callback) -> callbackId` shape.
 *
 * @param Handle Native handle type. Kept abstract so per-component
 *   handle wrappers (`Long` for LLM/VoiceAgent today; future opaque
 *   wrappers tomorrow) can plug in without changing the generic.
 * @param Event Proto event type. Must extend Wire's [Message] so the
 *   adapter can statically narrow the [decodeEvent] return type. The
 *   decode closure itself is injected, mirroring Swift's `Event(serializedBytes:)`
 *   indirection (Wire's `ADAPTER` lives on the companion of each generated
 *   class — Kotlin generics cannot reach it without reflection).
 *
 * @param handle The native handle the C registration targets.
 * @param streamKey Identifier that partitions the global fan-out store
 *   by adapter kind. Two adapter instances that share the same `Handle`
 *   type but call different `register` symbols must use distinct
 *   `streamKey` values; otherwise their fan-outs collide. Pass a stable
 *   string such as `"llm"` or `"voice-agent"`.
 * @param register Closure that installs the C-side callback for [handle].
 *   Must return a non-zero callback id on success or
 *   [INVALID_CALLBACK_ID] (0) on failure.
 * @param unregister Closure that tears down the C-side registration
 *   identified by `callbackId`. Pass a no-op id-less closure if your ABI
 *   uses a NULL-callback re-installation pattern (mirror Swift's
 *   VoiceAgent specialization).
 * @param decodeEvent Closure that parses one proto-byte payload into
 *   an [Event]. Typically `{ bytes -> Event.ADAPTER.decode(bytes) }`.
 * @param isTerminalEvent Optional predicate that classifies an event
 *   as terminal. When non-null and an event satisfies it, every
 *   collector is closed and the C registration is torn down. Omit to
 *   get pure fan-out semantics (events flow until subscribers detach).
 */
class HandleStreamAdapter<Handle : Any, Event : Message<*, *>>(
    private val handle: Handle,
    private val streamKey: String,
    private val register: (Handle, (ByteArray) -> Unit) -> Long,
    private val unregister: (Handle, Long) -> Unit,
    private val decodeEvent: (ByteArray) -> Event,
    private val isTerminalEvent: ((Event) -> Boolean)? = null,
) {
    /**
     * Start a new subscription. The returned [Flow] emits one decoded
     * [Event] per byte payload delivered by the C callback.
     *
     * Calling `stream()` twice attaches two collectors to the same
     * per-handle native callback registration. Each collector observes
     * every event in order, with its own unbounded channel so the C
     * dispatcher never blocks. Mirrors Swift's `AsyncStream` (default
     * `.unbounded`) and the React Native generateStream queue — a slow
     * collector grows its own buffer rather than losing events.
     */
    fun stream(): Flow<Event> =
        callbackFlow<Event> {
            val fanOut = fanOutFor(streamKey, handle, register, unregister, decodeEvent, isTerminalEvent)
            val channel: SendChannel<Event> = channel
            val added = fanOut.attach(channel)
            if (!added) {
                close(
                    IllegalStateException(
                        "HandleStreamAdapter[$streamKey]: register() returned " +
                            "INVALID_CALLBACK_ID — C-side registration failed.",
                    ),
                )
                return@callbackFlow
            }

            awaitClose { fanOut.detach(channel) }
        }.buffer(
            // Per-collector unbounded buffer. Matches Swift's `AsyncStream`
            // (which defaults to `.unbounded`) and the React Native
            // generateStream queue (an unbounded JS array). The C callback
            // thread invokes `trySend` on this channel and must never
            // block; `Channel.UNLIMITED` makes `trySend` non-blocking and
            // lossless, so a slow collector grows its own buffer rather
            // than dropping events that Swift/RN would have delivered.
            capacity = Channel.UNLIMITED,
        )

    /**
     * Force-tear down the per-handle registration regardless of
     * outstanding subscribers. Subscribers' flows complete normally.
     * Intended for use during component destruction; ordinary
     * cancellation should rely on the collector being cancelled.
     */
    fun tearDown() {
        val key = StoreKey(streamKey, handle)
        val fanOut =
            synchronized(fanOutsLock) {
                @Suppress("UNCHECKED_CAST")
                fanOuts[key] as HandleFanOut<Event>?
            }
        fanOut?.forceTearDown()
    }

    // Per-handle fan-out

    /**
     * Owns the single C-side registration for a specific (streamKey,
     * handle) pair and fans decoded events out to every attached
     * collector. Mirrors Swift's `HandleFanOut` inner class.
     */
    internal class HandleFanOut<Event : Message<*, *>>(
        private val handle: Any,
        private val storeKey: StoreKey,
        private val register: (Any, (ByteArray) -> Unit) -> Long,
        private val unregister: (Any, Long) -> Unit,
        private val decodeEvent: (ByteArray) -> Event,
        private val isTerminalEvent: ((Event) -> Boolean)?,
    ) {
        private val lock = Any()
        private val collectors = mutableListOf<SendChannel<Event>>()

        // Volatile so the C callback thread can read the latest id
        // without taking the lock for every dispatch.
        @Volatile
        private var callbackId: Long = INVALID_CALLBACK_ID

        /**
         * Installation state machine. Mirrors Swift's
         * `HandleStreamAdapter` install state (see Swift comment
         * record `mlt-002`): the C `register(...)` call MUST run outside
         * the per-fan-out lock so that
         *   (a) a same-thread synchronously-fired first callback observes
         *       the just-added collector in `collectors` (rather than the
         *       empty list it would see if we added AFTER register),
         *   (b) a cross-thread synchronously-fired first callback does
         *       not block on the lock the installer is still holding.
         */
        private enum class InstallState { NOT_INSTALLED, INSTALLING, INSTALLED }

        @Volatile
        private var installState: InstallState = InstallState.NOT_INSTALLED

        /**
         * Attach a collector. Returns `true` on success; returns `false`
         * (and leaves the fan-out state unchanged) if this was the
         * first subscriber AND the C-side registration failed, so the
         * caller can propagate the error to its own flow.
         *
         * Swift parity (mlt-002): the collector is appended to
         * `collectors` BEFORE the C `register()` call runs, and
         * `register()` runs OUTSIDE the per-fan-out lock. The first
         * attacher takes the `INSTALLING` role and performs the C-side
         * registration; concurrent attachers join as plain subscribers.
         */
        fun attach(channel: SendChannel<Event>): Boolean {
            val installer: Boolean =
                synchronized(lock) {
                    collectors.add(channel)
                    when (installState) {
                        InstallState.NOT_INSTALLED -> {
                            installState = InstallState.INSTALLING
                            true
                        }
                        // Already installed (or another caller is mid-install).
                        // Joining as a plain fan-out subscriber is sufficient;
                        // a same-thread synchronously-fired callback during the
                        // ongoing install will see this channel in `collectors`
                        // and broadcast() will deliver to it.
                        InstallState.INSTALLING, InstallState.INSTALLED -> false
                    }
                }

            if (!installer) return true

            // The C registration runs OUTSIDE the lock so that
            //   1. a synchronously-fired first callback that re-enters
            //      broadcast() can take the lock (snapshot collectors)
            //      and deliver the event,
            //   2. a cross-thread synchronous callback does not block on
            //      the installer's lock acquisition.
            val id = register(handle) { bytes -> broadcast(bytes) }
            if (id == INVALID_CALLBACK_ID) {
                // Roll back: drop EVERY collector that joined the
                // in-flight install (installer + joiners that appended
                // while we were INSTALLING), reset state to NOT_INSTALLED
                // so a fresh first subscriber can retry cleanly, then
                // close every snapshotted channel OUTSIDE the lock.
                //
                // Mirrors Swift's `install()` rollback at
                // HandleStreamAdapter.swift:189-207 which calls
                // `lockedState.continuations.removeAll()` and
                // `installation = .notInstalled`, then finishes every
                // pending continuation. Without dropping joiners here,
                // their flows hang forever in `awaitClose` on a fan-out
                // that has no live C registration to feed it.
                //
                // Lock-ordering rule (mirrors decode-failure path in
                // broadcast()): snapshot + clear under the lock, then
                // RELEASE the lock before closing channels.
                val snapshot: List<SendChannel<Event>> =
                    synchronized(lock) {
                        val s = collectors.toList()
                        collectors.clear()
                        installState = InstallState.NOT_INSTALLED
                        s
                    }
                for (c in snapshot) c.close()
                return false
            }
            return synchronized(lock) {
                callbackId = id
                installState = InstallState.INSTALLED
                true
            }
        }

        /**
         * Detach a collector. When the last collector detaches the C
         * registration is torn down and this fan-out is removed from
         * the global registry.
         *
         * `unregister` and `removeFanOut` are invoked OUTSIDE
         * `synchronized(lock)`. The C unregister contract may serialise
         * on in-flight callback invocations, so calling it under the
         * per-fan-out lock — which broadcast() also acquires from the
         * native callback thread — risks an ABBA deadlock between two
         * concurrent JNI callback threads. Mirrors Swift's
         * `HandleStreamAdapter.tearDown` ordering.
         */
        fun detach(channel: SendChannel<Event>) {
            val idToUnregister: Long =
                synchronized(lock) {
                    collectors.remove(channel)
                    if (collectors.isEmpty() && callbackId != INVALID_CALLBACK_ID) {
                        val id = callbackId
                        callbackId = INVALID_CALLBACK_ID
                        installState = InstallState.NOT_INSTALLED
                        id
                    } else {
                        INVALID_CALLBACK_ID
                    }
                }
            if (idToUnregister != INVALID_CALLBACK_ID) {
                removeFanOut(storeKey)
                unregister(handle, idToUnregister)
            }
        }

        /**
         * Force teardown ignoring outstanding collectors.
         *
         * Lock-ordering rule: snapshot collector list and capture the
         * callback id under the lock, clear internal state under the
         * lock, then release the lock before calling `unregister`,
         * `removeFanOut`, and closing channels. See [detach] for the
         * deadlock rationale.
         */
        fun forceTearDown() {
            val snapshot: List<SendChannel<Event>>
            val idToUnregister: Long =
                synchronized(lock) {
                    snapshot = collectors.toList()
                    collectors.clear()
                    val id = callbackId
                    callbackId = INVALID_CALLBACK_ID
                    installState = InstallState.NOT_INSTALLED
                    id
                }
            if (idToUnregister != INVALID_CALLBACK_ID) {
                removeFanOut(storeKey)
                unregister(handle, idToUnregister)
            }
            for (c in snapshot) c.close()
        }

        /** Visible for testing: number of attached collectors. */
        internal fun collectorCount(): Int = synchronized(lock) { collectors.size }

        /** Visible for testing: whether the C callback is currently installed. */
        internal fun isRegistered(): Boolean = callbackId != INVALID_CALLBACK_ID

        private fun broadcast(bytes: ByteArray) {
            val event =
                try {
                    decodeEvent(bytes)
                } catch (t: Throwable) {
                    // Malformed frame: surface the decode failure to every
                    // collector and tear down — broadcasting garbage is
                    // strictly worse than failing fast (matches Swift's
                    // `finishAll()` on decode failure).
                    //
                    // Lock-ordering rule (mirrors Swift): snapshot +
                    // clear under the lock, then RELEASE the lock
                    // before calling `unregister`, `removeFanOut`,
                    // and closing channels. broadcast() runs on a C
                    // callback thread; many native unregister contracts
                    // serialise on in-flight callbacks, so holding the
                    // per-fan-out lock through unregister can deadlock
                    // a second concurrent JNI callback thread that is
                    // already waiting to acquire the same lock.
                    val snapshot: List<SendChannel<Event>>
                    val idToUnregister: Long =
                        synchronized(lock) {
                            snapshot = collectors.toList()
                            collectors.clear()
                            val id = callbackId
                            if (callbackId != INVALID_CALLBACK_ID) {
                                callbackId = INVALID_CALLBACK_ID
                            }
                            installState = InstallState.NOT_INSTALLED
                            id
                        }
                    if (idToUnregister != INVALID_CALLBACK_ID) {
                        removeFanOut(storeKey)
                        unregister(handle, idToUnregister)
                    }
                    for (c in snapshot) c.close(t)
                    return
                }

            val isFinal = isTerminalEvent?.invoke(event) ?: false

            // Snapshot collectors under the lock so concurrent attach /
            // detach can't observe a torn list mid-broadcast. Capture
            // the callback id to unregister AFTER the lock is released
            // (see decode-error path above for the deadlock rationale).
            val snapshot: List<SendChannel<Event>>
            val idToUnregister: Long =
                synchronized(lock) {
                    snapshot = collectors.toList()
                    if (isFinal) {
                        collectors.clear()
                        val id = callbackId
                        if (callbackId != INVALID_CALLBACK_ID) {
                            callbackId = INVALID_CALLBACK_ID
                        }
                        installState = InstallState.NOT_INSTALLED
                        id
                    } else {
                        INVALID_CALLBACK_ID
                    }
                }

            if (isFinal && idToUnregister != INVALID_CALLBACK_ID) {
                removeFanOut(storeKey)
                unregister(handle, idToUnregister)
            }

            for (c in snapshot) {
                // Non-blocking offer: the per-collector channel is
                // configured with `Channel.UNLIMITED` (see stream()), so
                // `trySend` is lossless and never suspends this native
                // callback thread. Matches Swift's `AsyncStream` yield
                // semantics (unbounded buffer, non-blocking producer).
                c.trySend(event)
                if (isFinal) c.close()
            }
        }
    }

    // Global per-handle fan-out registry

    companion object {
        /**
         * Sentinel returned by [register] when the C-side installation
         * fails. Mirrors Swift's `result != RAC_SUCCESS` branch which
         * leaves no native registration in place.
         */
        const val INVALID_CALLBACK_ID: Long = 0L

        /**
         * Historical name retained for reference: per-collector channel
         * capacity used to be 64 with DROP_OLDEST. Since the policy
         * switched to `Channel.UNLIMITED` for Swift `AsyncStream` parity,
         * the constant is no longer wired in but is kept exposed for
         * legacy tests that pinned the older bounded-buffer behavior.
         */
        internal const val COLLECTOR_BUFFER_CAPACITY: Int = 64

        // Backed by a `MutableMap` + monitor rather than
        // `ConcurrentHashMap` so the generic stays in `commonMain`
        // (KMP commonMain has no java.util.concurrent). Critical
        // sections are O(1) and contention is low.
        private val fanOutsLock = Any()
        private val fanOuts = mutableMapOf<StoreKey, Any>()

        /**
         * Look up (or lazily create) the fan-out for a `(streamKey, handle)`
         * pair. The cast at the call site is guarded by streamKey, which
         * partitions the map across all generic specializations.
         */
        private fun <H : Any, E : Message<*, *>> fanOutFor(
            streamKey: String,
            handle: H,
            register: (H, (ByteArray) -> Unit) -> Long,
            unregister: (H, Long) -> Unit,
            decodeEvent: (ByteArray) -> E,
            isTerminalEvent: ((E) -> Boolean)?,
        ): HandleFanOut<E> {
            val key = StoreKey(streamKey, handle)
            synchronized(fanOutsLock) {
                val existing = fanOuts[key]
                if (existing != null) {
                    @Suppress("UNCHECKED_CAST")
                    return existing as HandleFanOut<E>
                }
                // Erase the Handle param through `Any` so the registry
                // can hold heterogeneous specializations under one map.
                // streamKey partitions, so the cast inside the fan-out
                // is sound.
                @Suppress("UNCHECKED_CAST")
                val fanOut =
                    HandleFanOut<E>(
                        handle = handle,
                        storeKey = key,
                        register = register as (Any, (ByteArray) -> Unit) -> Long,
                        unregister = unregister as (Any, Long) -> Unit,
                        decodeEvent = decodeEvent,
                        isTerminalEvent = isTerminalEvent,
                    )
                fanOuts[key] = fanOut
                return fanOut
            }
        }

        internal fun removeFanOut(key: StoreKey) {
            synchronized(fanOutsLock) { fanOuts.remove(key) }
        }

        /** Visible for testing: total number of live fan-outs. */
        internal fun activeFanOutCount(): Int = synchronized(fanOutsLock) { fanOuts.size }

        /** Visible for testing: look up an existing fan-out by key components. */
        internal fun <E : Message<*, *>> fanOutForTesting(streamKey: String, handle: Any): HandleFanOut<E>? {
            synchronized(fanOutsLock) {
                @Suppress("UNCHECKED_CAST")
                return fanOuts[StoreKey(streamKey, handle)] as HandleFanOut<E>?
            }
        }
    }

    /**
     * Composite key partitioning the global fan-out registry. The
     * `streamKey` distinguishes adapters that share the same handle
     * type but address different C registration ABIs (e.g. an LLM
     * stream and a future tool-call stream that share a `Long`
     * handle but use different register/unregister symbols).
     *
     * Equality on `handle` uses its native `equals` — for `Long` that
     * is value equality, which is what we want for native handles
     * received from C as opaque integer ids.
     */
    internal data class StoreKey(
        val streamKey: String,
        val handle: Any,
    )
}
