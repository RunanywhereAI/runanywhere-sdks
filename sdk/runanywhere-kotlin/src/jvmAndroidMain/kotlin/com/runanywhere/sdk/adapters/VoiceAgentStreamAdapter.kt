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
 * Cancellation: `Flow` collection cancellation propagates through
 * `awaitClose` to the JNI bridge which deregisters the C callback.
 */

package com.runanywhere.sdk.adapters

import com.runanywhere.sdk.generated.VoiceEvent  // Wire-generated; see GAP 01.
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Streams [VoiceEvent]s from a C++ voice agent handle.
 *
 * The adapter holds onto the handle but does NOT own its lifecycle —
 * callers create the handle elsewhere (typically via
 * `RunAnywhere.voiceAgent.create(...)`) and pass it in.
 *
 * Backpressure: the underlying flow is buffered (BUFFERED capacity ~64
 * with DROP_OLDEST overflow) so a slow consumer drops the oldest event
 * rather than blocking the C++ dispatcher. This matches the spec's
 * recommendation that audio/event streams favor liveness over completeness
 * for late subscribers.
 */
class VoiceAgentStreamAdapter(private val handle: Long) {

    /**
     * Open a new event subscription. Each call creates an independent C
     * registration; multiple collectors yield independent flows.
     */
    fun stream(): Flow<VoiceEvent> = callbackFlow<VoiceEvent> {
        val callbackId = nativeRegisterCallback(handle) { bytes ->
            // Wire's decode is byte-array-friendly. ProtoAdapter parsing is
            // O(message-size), no allocations beyond the resulting object.
            val event = try {
                VoiceEvent.ADAPTER.decode(bytes)
            } catch (t: Throwable) {
                close(t)
                return@nativeRegisterCallback
            }
            // trySendBlocking respects the configured buffer; DROP_OLDEST
            // ensures audio dispatcher is never blocked by a slow consumer.
            trySendBlocking(event)
        }

        if (callbackId == INVALID_CALLBACK_ID) {
            close(IllegalStateException(
                "rac_voice_agent_set_proto_callback failed (Protobuf may not be linked)"
            ))
            return@callbackFlow
        }

        awaitClose { nativeUnregisterCallback(handle, callbackId) }
    }

    private companion object {
        private const val INVALID_CALLBACK_ID: Long = 0L

        init {
            System.loadLibrary("rac_commons")
        }

        /**
         * JNI bridge: registers a Kotlin function as the proto-byte
         * callback for [handle], returning an opaque callbackId used to
         * deregister.
         *
         * Implementation lives in the JNI bridge .cpp under
         * `sdk/runanywhere-commons/src/infrastructure/jni_bridge/`. Until
         * the bridge ships, this declaration links against an `external`
         * symbol provided by the JNI .so loaded above.
         */
        @JvmStatic
        external fun nativeRegisterCallback(
            handle: Long,
            cb: (ByteArray) -> Unit
        ): Long

        @JvmStatic
        external fun nativeUnregisterCallback(handle: Long, callbackId: Long)
    }
}
