/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeSTT.kt
 *
 * STT component bridge — manages C++ STT component lifecycle and the
 * proto-canonical `rac_stt_*_proto` C ABI.
 *
 * All generic scaffolding (handle creation, isLoaded, loadModel, unload,
 * destroy) lives in [ComponentActor]; this object only adds the
 * STT-specific surfaces (`transcribe`, `transcribeStream`, `cancel`) on
 * top.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+STT.swift` (W3-2).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.STTAudioSource
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTStreamEvent
import ai.runanywhere.proto.v1.STTTranscriptionRequest
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RASTTOutput
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
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+STT.swift`. Wraps
 * `rac_stt_*_proto` C ABI. Handle lifecycle lives in [inner].
 */
object CppBridgeSTT {
    /** Generic scaffold (handle / isLoaded / loadModel / unload / destroy). */
    private val inner = ComponentActor(ComponentVTable.stt)

    private val logger = SDKLogger("CppBridge.STT")

    // MARK: - Handle Management

    /** Get or create the STT component handle. */
    suspend fun getHandle(): Long = inner.getHandle()

    // MARK: - State

    /** Whether a model is loaded. */
    val isLoaded: Boolean
        get() = inner.isLoaded

    /** Currently-loaded model id, or null. */
    val currentModelId: String?
        get() = inner.currentAssetId

    /**
     * Whether the STT component supports streaming transcription.
     *
     * Returns `false` if the underlying C handle has not yet been created.
     * Mirrors Swift's `var supportsStreaming: Bool` computed property on
     * `CppBridge.STT`.
     */
    suspend fun supportsStreaming(): Boolean {
        val handle = inner.existingHandle()
        if (handle == 0L) return false
        return RunAnywhereBridge.racSttComponentSupportsStreaming(handle)
    }

    // MARK: - Model Lifecycle

    /**
     * Load an STT model. Routes through the canonical lifecycle proto path.
     *
     * When [framework] is not [CppBridgeModelRegistry.Framework.UNKNOWN], the
     * component is configured with that preferred framework before the
     * lifecycle load — so telemetry events carry the real framework value
     * instead of "unknown". Mirrors Swift's
     * `loadModel(_:modelId:modelName:framework:)`.
     *
     * @param framework The `rac_inference_framework_t` int (see
     *   [CppBridgeModelRegistry.Framework]). Defaults to `UNKNOWN`, which
     *   skips the configure step entirely.
     */
    suspend fun loadModel(
        modelPath: String,
        modelId: String,
        modelName: String,
        framework: Int = CppBridgeModelRegistry.Framework.UNKNOWN,
    ) {
        if (framework != CppBridgeModelRegistry.Framework.UNKNOWN) {
            val handle = inner.getHandle()
            val rc = RunAnywhereBridge.racSttComponentConfigure(handle, framework)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                logger.warning("Failed to configure STT framework: rc=$rc")
            }
        }
        inner.loadModel(path = modelPath, id = modelId, name = modelName)
    }

    /** Unload the current model. */
    suspend fun unload() {
        inner.unload()
    }

    // MARK: - Cleanup

    /** Destroy the component. */
    suspend fun destroy() {
        inner.destroy()
    }

    // MARK: - STT-specific operations

    /** Cancel any in-flight transcription. No-op if the handle is not created. */
    suspend fun cancel() {
        val handle = inner.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racSttComponentCancel(handle)
    }

    /**
     * One-shot transcription via lifecycle-loaded STT model.
     *
     * Mirrors iOS Swift's `RunAnywhere.transcribe(...)` which builds an
     * `RASTTTranscriptionRequest` and calls `rac_stt_transcribe_lifecycle_proto`.
     * The component handle is intentionally unused — the lifecycle is the
     * source of truth for "is an STT model loaded".
     */
    suspend fun transcribe(audioData: ByteArray, options: RASTTOptions): RASTTOutput {
        val request = STTTranscriptionRequest(
            audio = STTAudioSource(audio_data = okio.ByteString.of(*audioData)),
            options = options,
        )
        return decodeOrThrow(
            STTOutput.ADAPTER,
            RunAnywhereBridge.racSttTranscribeLifecycleProto(
                STTTranscriptionRequest.ADAPTER.encode(request),
            ),
            "racSttTranscribeLifecycleProto",
        )
    }

    /**
     * Streaming transcription via lifecycle-loaded STT model. Native emits
     * canonical [STTStreamEvent] envelopes (STARTED / PARTIAL / FINAL / ERROR
     * with monotonically-increasing seq and timestamp_us). Kotlin simply
     * decodes and forwards. Mirrors Swift's
     * `rac_stt_transcribe_stream_lifecycle_proto` call site.
     */
    suspend fun transcribeStream(
        audioData: ByteArray,
        options: RASTTOptions,
        onEvent: (STTStreamEvent) -> Boolean,
    ) {
        val request = STTTranscriptionRequest(
            audio = STTAudioSource(audio_data = okio.ByteString.of(*audioData)),
            options = options,
        )
        val rc =
            RunAnywhereBridge.racSttTranscribeStreamLifecycleProto(
                STTTranscriptionRequest.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onEvent(STTStreamEvent.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racSttTranscribeStreamLifecycleProto")
    }
}
