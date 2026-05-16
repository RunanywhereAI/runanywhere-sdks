/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeTTS.kt
 *
 * TTS component bridge — manages C++ TTS component lifecycle and the
 * proto-canonical `rac_tts_*_proto` C ABI.
 *
 * All generic scaffolding (handle creation, isLoaded, loadVoice, unload,
 * destroy) lives in [ComponentActor]; this object only adds the
 * TTS-specific surfaces (`voices`, `synthesize`, `synthesizeStream`,
 * `stop`) on top. The vtable's `loadModel` slot is the C ABI's
 * `rac_tts_component_load_voice` — TTS calls it "voice", the actor calls
 * it "asset" — semantically identical.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+TTS.swift` (W3-3).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSSynthesisRequest
import ai.runanywhere.proto.v1.TTSVoiceInfo
import ai.runanywhere.proto.v1.TTSVoiceList
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

private fun <M : Message<M, *>> decodeOrThrow(
    adapter: ProtoAdapter<M>,
    bytes: ByteArray?,
    operation: String,
): M {
    val payload = bytes ?: throw SDKException.operation("$operation returned null")
    return try {
        adapter.decode(payload)
    } catch (e: Exception) {
        throw SDKException.operation("Failed to decode $operation result: ${e.message}")
    }
}

private fun checkRc(rc: Int, operation: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$operation failed with rc=$rc")
    }
}

/**
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+TTS.swift`. Wraps
 * `rac_tts_*_proto` C ABI. Handle lifecycle lives in [inner].
 */
object CppBridgeTTS {
    /** Generic scaffold (handle / isLoaded / loadVoice / unload / destroy). */
    internal val inner = ComponentActor(ComponentVTable.tts)

    // MARK: - Handle Management

    /** Get or create the TTS component handle. */
    suspend fun getHandle(): Long = inner.getHandle()

    // MARK: - State

    /** Currently-loaded voice id, or null. */
    val currentVoiceId: String?
        get() = inner.currentAssetId

    // MARK: - Voice Lifecycle

    /**
     * Load a TTS voice. Routes through the canonical lifecycle proto path
     * (the vtable's `loadModel` slot is the C ABI's
     * `rac_tts_component_load_voice`).
     */
    suspend fun loadVoice(voicePath: String, voiceId: String, voiceName: String) {
        inner.loadModel(path = voicePath, id = voiceId, name = voiceName)
    }

    /** Unload the current voice. */
    suspend fun unload() {
        inner.unload()
    }

    // MARK: - Cleanup

    /** Destroy the component. */
    suspend fun destroy() {
        inner.destroy()
    }

    // MARK: - TTS-specific operations

    /**
     * Stop any in-flight synthesis on the lifecycle-loaded TTS voice.
     *
     * Routes through `rac_tts_stop_lifecycle_proto`, mirroring Swift's
     * lifecycle TTS stop ABI. The v2 public TTS path
     * (`synthesizeStream` → `racTtsSynthesizeStreamLifecycleProto`)
     * never creates the legacy ComponentActor handle, so the previous
     * `racTtsComponentCancel(handle)` no-op did not actually stop the
     * native synthesis. This call returns serialized `TTSServiceState`
     * bytes; we ignore them — the caller only cares that the native
     * synthesis is asked to stop.
     */
    suspend fun stop() {
        // racTtsStopLifecycleProto is safe to call even when no voice is
        // loaded: the C ABI returns RAC_ERROR_INVALID_STATE in that case.
        RunAnywhereBridge.racTtsStopLifecycleProto()
    }

    /**
     * Enumerate the voices available to the loaded TTS backend.
     *
     * Mirrors iOS Swift's `rac_tts_list_voices_lifecycle_proto` call site —
     * the lifecycle is the source of truth, no handle is threaded.
     */
    suspend fun voices(): List<TTSVoiceInfo> {
        val bytes =
            RunAnywhereBridge.racTtsListVoicesLifecycleProto()
                ?: throw SDKException.operation("racTtsListVoicesLifecycleProto returned null")
        return TTSVoiceList.ADAPTER.decode(bytes).voices
    }

    /**
     * One-shot synthesis via lifecycle-loaded TTS model.
     *
     * Mirrors iOS Swift's `rac_tts_synthesize_lifecycle_proto` which takes a
     * serialized `TTSSynthesisRequest` and resolves the lifecycle-loaded TTS
     * model internally — no component handle required.
     */
    suspend fun synthesize(text: String, options: RATTSOptions): RATTSOutput {
        val request = TTSSynthesisRequest(text = text, options = options)
        return decodeOrThrow(
            TTSOutput.ADAPTER,
            RunAnywhereBridge.racTtsSynthesizeLifecycleProto(
                TTSSynthesisRequest.ADAPTER.encode(request),
            ),
            "racTtsSynthesizeLifecycleProto",
        )
    }

    /**
     * Streaming synthesis. Native emits canonical [TTSOutput] envelopes;
     * Kotlin simply decodes and forwards. Routes through
     * `rac_tts_synthesize_stream_lifecycle_proto`, mirroring iOS.
     */
    suspend fun synthesizeStream(
        text: String,
        options: RATTSOptions,
        onChunk: (RATTSOutput) -> Boolean,
    ) {
        val request = TTSSynthesisRequest(text = text, options = options)
        val rc =
            RunAnywhereBridge.racTtsSynthesizeStreamLifecycleProto(
                TTSSynthesisRequest.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onChunk(TTSOutput.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racTtsSynthesizeStreamLifecycleProto")
    }
}
