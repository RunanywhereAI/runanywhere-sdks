/*
 * VoiceAgentStreamAdapter.kt
 *
 * Mirror of Swift's `Sources/RunAnywhere/Adapters/VoiceAgentStreamAdapter.swift`.
 *
 * Was ~244 LOC of duplicated fan-out machinery (per-handle registry,
 * synchronized collector list, JNI lambda trampoline) — bit-for-bit
 * identical to `LLMStreamAdapter` except for the proto event type and
 * the C register/unregister symbols. Phase W2-5 extracted that
 * machinery into the generic `HandleStreamAdapter<Handle, Event>` in
 * `commonMain/adapters/HandleStreamAdapter.kt`; this file is now a thin
 * specialization that wires the voice-agent-specific JNI symbols.
 *
 * Why this class stays in `jvmAndroidMain` (not `commonMain`):
 *   The C JNI thunks in `runanywhere_commons_jni.cpp` mangle into
 *   `Java_com_runanywhere_sdk_adapters_VoiceAgentStreamAdapter_00024JniBridge_*`,
 *   so the `JniBridge` inner object MUST live under exactly this class
 *   path. Moving the class to `commonMain` (where `external fun` is
 *   forbidden) would orphan those symbols and the runtime would throw
 *   `UnsatisfiedLinkError`. The generic itself lives in `commonMain`;
 *   this file is the platform-side wiring.
 *
 * Public API (preserved):
 *     val flow: Flow<VoiceEvent> = VoiceAgentStreamAdapter(handle).stream()
 *     flow.collect { event -> handle(event) }
 *
 * Voice events fan out forever (no terminal-event predicate); consumers
 * exit the stream by cancelling their collector.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.VoiceEvent
import com.runanywhere.sdk.public.types.RAVoiceEvent
import kotlinx.coroutines.flow.Flow

/**
 * Streams [RAVoiceEvent]s from a C++ voice agent handle.
 *
 * The adapter holds onto the handle but does NOT own its lifecycle —
 * callers create the handle elsewhere (typically via
 * `CppBridgeVoiceAgent.getHandle()`) and pass it in.
 *
 * Fan-out semantics: the underlying C ABI exposes a SINGLE
 * proto-callback slot per handle. The generic [HandleStreamAdapter]
 * installs one C-side registration lazily for the first subscriber and
 * tears it down when the last subscriber detaches, fanning each
 * decoded event out to every active collector.
 */
class VoiceAgentStreamAdapter internal constructor(
    private val handle: Long,
    private val bridge: NativeBridge,
) {
    /** Public primary constructor: wire to the real JNI bridge. */
    constructor(handle: Long) : this(handle, JniBridge)

    // Bridge identity is folded into the streamKey so multiple
    // adapters that share a handle but use different bridges (the
    // production JNI vs. a test fake) get isolated fan-out state.
    // Production uses the JniBridge singleton so this collapses to a
    // single stable key under normal use.
    private val streamKey: String = "voice-agent#${System.identityHashCode(bridge)}"

    private val delegate: HandleStreamAdapter<Long, VoiceEvent> =
        HandleStreamAdapter(
            handle = handle,
            streamKey = streamKey,
            register = { h, cb -> bridge.registerCallback(h, cb) },
            unregister = { h, id -> bridge.unregisterCallback(h, id) },
            quiesce = { bridge.quiesce() },
            decodeEvent = { bytes -> VoiceEvent.ADAPTER.decode(bytes) },
            // Voice agents have no terminal event — collectors detach
            // explicitly. Mirrors Swift's VoiceAgent convenience init.
            isTerminalEvent = null,
        )

    /**
     * Open a new event subscription. Multiple collectors on the same
     * handle share a single C callback registration and each receives
     * the full decoded event sequence.
     */
    fun stream(): Flow<RAVoiceEvent> = delegate.stream()

    /**
     * SPI seam that lets tests substitute a fake producer in place of
     * the JNI trampoline. Production code uses [JniBridge]; tests use a
     * fake that invokes the supplied callback directly.
     */
    internal interface NativeBridge {
        /**
         * Install [cb] as the proto-byte callback for [handle]. Returns
         * a non-zero opaque id on success, or [INVALID_CALLBACK_ID] on
         * failure.
         */
        fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long

        /** Tear down the registration identified by [callbackId]. */
        fun unregisterCallback(handle: Long, callbackId: Long)

        /** Wait for in-flight native callback dispatches to return. */
        fun quiesce()
    }

    internal companion object {
        /** Mirrors the generic's sentinel so test bridges can return it. */
        internal const val INVALID_CALLBACK_ID: Long = HandleStreamAdapter.INVALID_CALLBACK_ID

        /**
         * Visible-for-testing accessor: total number of live fan-outs
         * across every `(streamKey, handle)` pair. Used by the
         * `VoiceAgentStreamAdapterFanOutTest` reset loop to detect leaks.
         */
        internal fun activeFanOutCount(): Int = HandleStreamAdapter.activeFanOutCount()

        /**
         * Visible-for-testing accessor that returns a live view of the
         * fan-out for a `(handle, bridge)` pair. The returned view
         * re-resolves the underlying [HandleStreamAdapter.HandleFanOut]
         * on every method call, so polling loops in tests
         * (`awaitCollectorCount`) can observe registration appearing
         * after a collector subscribes without first asserting
         * non-null.
         */
        internal fun fanOutFor(
            handle: Long,
            bridge: NativeBridge,
        ): FanOutView {
            val key = "voice-agent#${System.identityHashCode(bridge)}"
            return FanOutView(key, handle)
        }

        /**
         * Live view onto a (streamKey, handle) fan-out slot. Methods
         * return a snapshot of the current state — `0` / `false` when
         * no subscribers have attached yet. Returning a value-based
         * view (rather than the underlying mutable
         * [HandleStreamAdapter.HandleFanOut]) keeps the generic's
         * internal class out of the public test surface.
         */
        internal class FanOutView(
            private val streamKey: String,
            private val handle: Long,
        ) {
            internal fun collectorCount(): Int {
                val fanOut = HandleStreamAdapter.fanOutForTesting<VoiceEvent>(streamKey, handle)
                return fanOut?.collectorCount() ?: 0
            }

            internal fun isRegistered(): Boolean {
                val fanOut = HandleStreamAdapter.fanOutForTesting<VoiceEvent>(streamKey, handle)
                return fanOut?.isRegistered() == true
            }
        }
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

        override fun quiesce() = nativeQuiesce()

        /**
         * JNI bridge: registers a Kotlin lambda as the proto-byte
         * callback for [handle]. The thunk stores the lambda in a global
         * ref + context object, then calls `rac_voice_agent_set_proto_callback`
         * with a C trampoline that re-dispatches bytes back to the JVM.
         *
         * Returns an opaque `callbackId` (the context pointer cast to
         * jlong); [nativeUnregisterCallback] uses it to null the C
         * callback and release the global ref. Returns 0 on failure.
         */
        @JvmStatic
        private external fun nativeRegisterCallback(
            handle: Long,
            cb: (ByteArray) -> Unit,
        ): Long

        @JvmStatic
        private external fun nativeUnregisterCallback(handle: Long, callbackId: Long)

        @JvmStatic
        private external fun nativeQuiesce()
    }
}
