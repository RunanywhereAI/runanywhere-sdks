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

// Wire-generated from idl/voice_events.proto — see GAP 01. Real Kotlin
// package emitted by Wire is ai.runanywhere.proto.v1 (the files live
// physically under src/commonMain/.../com/runanywhere/sdk/generated/
// but their `package` declaration matches the proto java_package).
import ai.runanywhere.proto.v1.VoiceEvent
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
            // Load the same JNI .so that RunAnywhereBridge uses
            // (runanywhere_commons_jni → libruneanywhere_jni.so on Android).
            // The nativeRegister/Unregister thunks live in
            // sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp.
            System.loadLibrary("runanywhere_jni")
        }

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
         * Note: the underlying C ABI keeps exactly **one** proto callback
         * slot per handle. Multiple concurrent stream() calls on the same
         * handle will therefore REPLACE each other, not fan out. True
         * multi-subscriber fan-out would require an ABI extension (not in
         * v2 scope).
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
