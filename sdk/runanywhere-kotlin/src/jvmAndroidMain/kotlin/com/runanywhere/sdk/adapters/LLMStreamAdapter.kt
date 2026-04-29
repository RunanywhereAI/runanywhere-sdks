/*
 * LLMStreamAdapter.kt
 *
 * v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
 *
 * Wraps the C++ proto-byte LLM stream ABI
 * (`rac_llm_set_stream_proto_callback`, declared in `rac_llm_stream.h`)
 * as a Kotlin `Flow<LLMStreamEvent>`. `LLMStreamEvent` is the
 * Wire-generated type from `idl/llm_service.proto`.
 *
 * This is the unified LLM streaming path — the hand-rolled
 * `callbackFlow { CppBridgeLLM.generateStream(...) { token -> trySend(token) } }`
 * shim in `RunAnywhere+TextGeneration.jvmAndroid.kt` was DELETED in
 * the same change; the public `generateStream` now pulls from this
 * adapter and re-emits `event.token` for legacy callers that want the
 * bare token string.
 *
 * Public API:
 *     val flow: Flow<LLMStreamEvent> = LLMStreamAdapter(handle).stream()
 *     flow.collect { event ->
 *         if (event.isFinal) { ... } else print(event.token_)
 *     }
 *
 * Multi-collector fan-out (parity with VoiceAgentStreamAdapter):
 *   The underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   This adapter keeps a per-handle broadcaster that installs ONE C
 *   callback on first subscribe and tears it down when the last
 *   subscriber cancels.
 */

package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.LLMStreamEvent
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Streams [LLMStreamEvent]s from a C++ LLM component handle.
 *
 * The adapter holds onto the handle but does NOT own its lifecycle —
 * callers own the C++ component (via `CppBridgeLLM` / `RunAnywhere.loadModel`)
 * and pass its handle in.
 *
 * Backpressure: each collector gets its own buffered channel (capacity 64
 * with DROP_OLDEST overflow) so a slow consumer drops the oldest event
 * rather than blocking the C++ dispatcher.
 */
class LLMStreamAdapter internal constructor(
    private val handle: Long,
    private val bridge: NativeBridge,
) {
    /** Public primary constructor wires to the real JNI bridge. */
    constructor(handle: Long) : this(handle, JniBridge)

    /**
     * Open a new event subscription. Multiple collectors on the same
     * handle share a single C callback registration and each receives
     * the full decoded event sequence.
     */
    fun stream(): Flow<LLMStreamEvent> =
        callbackFlow<LLMStreamEvent> {
            val fanOut = fanOutFor(handle, bridge)
            val channel: SendChannel<LLMStreamEvent> = channel
            val added = fanOut.attach(channel)
            if (!added) {
                close(
                    IllegalStateException(
                        "rac_llm_set_stream_proto_callback failed (Protobuf may not be linked)",
                    ),
                )
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
        fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long

        fun unregisterCallback(handle: Long, callbackId: Long)
    }

    internal class HandleFanOut(
        private val handle: Long,
        private val bridge: NativeBridge,
        private val onTornDown: () -> Unit,
    ) {
        private val lock = Any()
        private val collectors = CopyOnWriteArrayList<SendChannel<LLMStreamEvent>>()

        @Volatile
        private var callbackId: Long = INVALID_CALLBACK_ID

        fun attach(channel: SendChannel<LLMStreamEvent>): Boolean {
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

        fun detach(channel: SendChannel<LLMStreamEvent>) {
            synchronized(lock) {
                collectors.remove(channel)
                if (collectors.isEmpty() && callbackId != INVALID_CALLBACK_ID) {
                    bridge.unregisterCallback(handle, callbackId)
                    callbackId = INVALID_CALLBACK_ID
                    onTornDown()
                }
            }
        }

        internal fun collectorCount(): Int = collectors.size

        internal fun isRegistered(): Boolean = callbackId != INVALID_CALLBACK_ID

        private fun broadcast(bytes: ByteArray) {
            val event =
                try {
                    LLMStreamEvent.ADAPTER.decode(bytes)
                } catch (t: Throwable) {
                    for (c in collectors) c.close(t)
                    return
                }
            for (c in collectors) c.trySendBlocking(event)
            // Close all channels when the stream is terminated so that
            // callbackFlow's awaitClose unblocks and the Flow completes.
            if (event.is_final) {
                for (c in collectors) c.close()
            }
        }
    }

    internal companion object {
        internal const val INVALID_CALLBACK_ID: Long = 0L

        private val fanOuts = ConcurrentHashMap<Pair<Long, NativeBridge>, HandleFanOut>()

        internal fun fanOutFor(handle: Long, bridge: NativeBridge): HandleFanOut {
            val key = handle to bridge
            return fanOuts.computeIfAbsent(key) {
                HandleFanOut(handle, bridge) { fanOuts.remove(key) }
            }
        }

        internal fun activeFanOutCount(): Int = fanOuts.size

        @Suppress("unused")
        internal const val STREAM_BUFFER_CAPACITY = 64

        @Suppress("unused")
        internal val STREAM_BUFFER_OVERFLOW = BufferOverflow.DROP_OLDEST
    }

    private object JniBridge : NativeBridge {
        init {
            System.loadLibrary("runanywhere_jni")
        }

        override fun registerCallback(handle: Long, cb: (ByteArray) -> Unit): Long =
            nativeRegisterCallback(handle, cb)

        override fun unregisterCallback(handle: Long, callbackId: Long) =
            nativeUnregisterCallback(handle, callbackId)

        /**
         * JNI thunk: installs a Kotlin lambda as the proto-byte callback
         * for [handle]. See runanywhere_commons_jni.cpp's
         * `Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_nativeRegisterCallback`.
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
