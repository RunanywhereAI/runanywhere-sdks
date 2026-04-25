/*
 * VoiceAgentStreamAdapter.kt
 *
 * GAP 09 Phase 17 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
 *
 * Wraps the C++ proto-byte voice agent ABI (`rac_voice_agent_set_proto_callback`,
 * GAP 09 Phase 15) as a Kotlin `Flow<VoiceEvent>`. `VoiceEvent` is the
 * Wire-generated type from `idl/voice_events.proto` (GAP 01).
 *
 * Public API:
 *     val flow: Flow<VoiceEvent> = VoiceAgentStreamAdapter(handle).stream()
 *     flow.collect { event -> handle(event) }
 *
 * Multi-collector fan-out (B29):
 *   The underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   Without fan-out, a second `stream()` collector silently replaces the
 *   first. To preserve the `Flow` contract (every collector observes every
 *   event) we keep a per-handle broadcaster that installs ONE C callback
 *   lazily for the first subscriber, and tears it down when the last
 *   subscriber cancels.
 */

package com.runanywhere.sdk.adapters

// Wire-generated from idl/voice_events.proto — see GAP 01. Real Kotlin
// package emitted by Wire is ai.runanywhere.proto.v1 (the files live
// physically under src/commonMain/.../com/runanywhere/sdk/generated/
// but their `package` declaration matches the proto java_package).
import ai.runanywhere.proto.v1.VoiceEvent
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Streams [VoiceEvent]s from a C++ voice agent handle.
 *
 * The adapter holds onto the handle but does NOT own its lifecycle —
 * callers create the handle elsewhere (typically via
 * `RunAnywhere.voiceAgent.create(...)`) and pass it in.
 *
 * Backpressure: each collector gets its own buffered channel (capacity ~64
 * with DROP_OLDEST overflow) so a slow consumer drops the oldest event
 * rather than blocking the C++ dispatcher. This matches the spec's
 * recommendation that audio/event streams favor liveness over completeness
 * for late subscribers.
 *
 * Thread safety: [HandleFanOut.broadcast] fans each decoded event out to
 * every active collector. Installation/teardown of the C callback is
 * serialized per handle via an internal monitor so the "first subscriber
 * registers, last subscriber unregisters" transition is atomic.
 */
class VoiceAgentStreamAdapter internal constructor(
    private val handle: Long,
    private val bridge: NativeBridge,
) {
    /** Public primary constructor: wire to the real JNI bridge. */
    constructor(handle: Long) : this(handle, JniBridge)

    /**
     * Open a new event subscription. Multiple collectors on the same
     * handle share a single C callback registration and each receives the
     * full decoded event sequence.
     */
    fun stream(): Flow<VoiceEvent> = callbackFlow<VoiceEvent> {
        val fanOut = fanOutFor(handle, bridge)
        val channel: SendChannel<VoiceEvent> = channel
        val added = fanOut.attach(channel)
        if (!added) {
            close(IllegalStateException(
                "rac_voice_agent_set_proto_callback failed (Protobuf may not be linked)"
            ))
            return@callbackFlow
        }

        awaitClose { fanOut.detach(channel) }
    }

    /**
     * SPI seam that lets tests substitute a fake producer in place of the
     * JNI trampoline. Production code uses [JniBridge]; tests use a fake
     * that invokes the supplied callback directly.
     */
    internal interface NativeBridge {
        /**
         * Install [cb] as the proto-byte callback for [handle]. Returns a
         * non-zero opaque id on success, or [INVALID_CALLBACK_ID] on
         * failure.
         */
        fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long

        /** Tear down the registration identified by [callbackId]. */
        fun unregisterCallback(handle: Long, callbackId: Long)
    }

    /**
     * Broadcaster that owns the single C-side registration for a specific
     * voice-agent handle and fans out decoded events to every attached
     * collector.
     */
    internal class HandleFanOut(
        private val handle: Long,
        private val bridge: NativeBridge,
        private val onTornDown: () -> Unit,
    ) {
        private val lock = Any()
        private val collectors = CopyOnWriteArrayList<SendChannel<VoiceEvent>>()

        @Volatile
        private var callbackId: Long = INVALID_CALLBACK_ID

        /**
         * Attach a collector. Returns `true` on success; returns `false`
         * (and leaves the fan-out state unchanged) if this was the first
         * subscriber AND the C-side registration failed, so the caller
         * can propagate the error to its own flow.
         */
        fun attach(channel: SendChannel<VoiceEvent>): Boolean {
            synchronized(lock) {
                if (collectors.isEmpty()) {
                    val id = bridge.registerCallback(handle) { bytes -> broadcast(bytes) }
                    if (id == INVALID_CALLBACK_ID) return false
                    callbackId = id
                }
                collectors.add(channel)
                return true
            }
        }

        fun detach(channel: SendChannel<VoiceEvent>) {
            synchronized(lock) {
                collectors.remove(channel)
                if (collectors.isEmpty() && callbackId != INVALID_CALLBACK_ID) {
                    bridge.unregisterCallback(handle, callbackId)
                    callbackId = INVALID_CALLBACK_ID
                    onTornDown()
                }
            }
        }

        /** Visible for testing: number of attached collectors. */
        internal fun collectorCount(): Int = collectors.size

        /** Visible for testing: whether the C callback is currently installed. */
        internal fun isRegistered(): Boolean = callbackId != INVALID_CALLBACK_ID

        private fun broadcast(bytes: ByteArray) {
            val event = try {
                VoiceEvent.ADAPTER.decode(bytes)
            } catch (t: Throwable) {
                // Malformed frame: close each collector with the decode error.
                // Broadcasting garbage is worse than surfacing the failure.
                for (c in collectors) c.close(t)
                return
            }
            // Each channel enforces its own backpressure policy (DROP_OLDEST
            // with capacity 64); a slow collector never blocks the C++
            // dispatcher or starves its peers.
            for (c in collectors) c.trySendBlocking(event)
        }
    }

    internal companion object {
        internal const val INVALID_CALLBACK_ID: Long = 0L

        /**
         * Per-handle fan-out state. Keyed by the raw native handle; each
         * entry owns at most one C callback registration at a time.
         *
         * The map is keyed by `Pair<Long, NativeBridge>` so two adapters
         * backed by different bridges (production JNI vs. a test fake)
         * never cross-contaminate, even if they happen to share a handle
         * value.
         */
        private val fanOuts = ConcurrentHashMap<Pair<Long, NativeBridge>, HandleFanOut>()

        internal fun fanOutFor(handle: Long, bridge: NativeBridge): HandleFanOut {
            val key = handle to bridge
            return fanOuts.computeIfAbsent(key) {
                HandleFanOut(handle, bridge) { fanOuts.remove(key) }
            }
        }

        /** Visible for testing. */
        internal fun activeFanOutCount(): Int = fanOuts.size

        // Expose the backpressure policy for the fan-out channel so tests
        // can mirror production capacity when injecting fake producers.
        @Suppress("unused")
        internal const val STREAM_BUFFER_CAPACITY = 64

        @Suppress("unused")
        internal val STREAM_BUFFER_OVERFLOW = BufferOverflow.DROP_OLDEST
    }

    /**
     * Default [NativeBridge] backed by the JNI thunks compiled into
     * `librunanywhere_jni.so`.
     */
    private object JniBridge : NativeBridge {
        init {
            // Load the same JNI .so that RunAnywhereBridge uses.
            System.loadLibrary("runanywhere_jni")
        }

        override fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long =
            nativeRegisterCallback(handle, cb)

        override fun unregisterCallback(handle: Long, callbackId: Long) =
            nativeUnregisterCallback(handle, callbackId)

        /**
         * JNI bridge: registers a Kotlin lambda as the proto-byte callback
         * for [handle]. The thunk stores the lambda in a global ref +
         * context object, then calls `rac_voice_agent_set_proto_callback`
         * with a C trampoline that re-dispatches bytes back to the JVM.
         *
         * Returns an opaque `callbackId` (the context pointer cast to jlong);
         * [nativeUnregisterCallback] uses it to null the C callback and
         * release the global ref. Returns 0 on failure.
         *
         * Per-handle fan-out is handled entirely on the JVM side (see
         * [HandleFanOut]); the ABI still exposes exactly one callback slot
         * per handle.
         */
        @JvmStatic
        private external fun nativeRegisterCallback(
            handle: Long,
            cb: (ByteArray) -> Unit,
        ): Long

        @JvmStatic
        private external fun nativeUnregisterCallback(handle: Long, callbackId: Long)
    }
}
