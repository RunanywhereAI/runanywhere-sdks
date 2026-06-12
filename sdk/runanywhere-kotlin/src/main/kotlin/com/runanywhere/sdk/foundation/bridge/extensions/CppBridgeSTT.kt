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

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.STTAudioSource
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTPartialResult
import ai.runanywhere.proto.v1.STTStreamEvent
import ai.runanywhere.proto.v1.STTStreamEventKind
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect

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
        val request =
            STTTranscriptionRequest(
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
        val request =
            STTTranscriptionRequest(
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

    /**
     * Incremental stream-in / stream-out transcription.
     *
     * Mirrors Swift's `transcribeSessionStream`: prepare a component handle
     * for the lifecycle-loaded model, register one proto callback, start a
     * session, feed each incoming audio chunk as it arrives, then stop or
     * cancel the session depending on collection outcome.
     */
    suspend fun transcribeSessionStream(
        audio: Flow<ByteArray>,
        options: RASTTOptions,
        loadedModel: CurrentModelResult,
        onPartial: (STTPartialResult) -> Boolean,
    ) {
        val handle = prepareStreamingHandle(loadedModel)
        var sessionId = 0L
        var shouldCancel = false

        val listener =
            NativeProtoProgressListener { bytes ->
                val partial = partialFromEvent(STTStreamEvent.ADAPTER.decode(bytes))
                partial?.let(onPartial) ?: true
            }

        checkRc(
            RunAnywhereBridge.racSttSetStreamProtoCallback(handle, listener),
            "racSttSetStreamProtoCallback",
        )

        try {
            val started = RunAnywhereBridge.racSttStreamStartProto(handle, RASTTOptions.ADAPTER.encode(options))
            if (started <= 0L) {
                throw SDKException.operation("racSttStreamStartProto failed with rc=$started")
            }
            sessionId = started

            audio.collect { chunk ->
                if (chunk.isEmpty()) return@collect
                val feedRc = RunAnywhereBridge.racSttStreamFeedAudioProto(sessionId, chunk)
                if (feedRc != RunAnywhereBridge.RAC_SUCCESS) {
                    onPartial(errorPartial("STT stream feed failed: $feedRc", feedRc))
                    shouldCancel = true
                    throw SDKException.operation("racSttStreamFeedAudioProto failed with rc=$feedRc")
                }
            }

            val stopRc = RunAnywhereBridge.racSttStreamStopProto(sessionId)
            if (stopRc != RunAnywhereBridge.RAC_SUCCESS) {
                onPartial(errorPartial("STT stream stop failed: $stopRc", stopRc))
            }
        } catch (e: CancellationException) {
            shouldCancel = true
            throw e
        } catch (e: Throwable) {
            shouldCancel = true
            throw e
        } finally {
            if (shouldCancel && sessionId > 0L) {
                RunAnywhereBridge.racSttStreamCancelProto(sessionId)
            }
            RunAnywhereBridge.racSttUnsetStreamProtoCallback(handle)
            RunAnywhereBridge.racSttProtoQuiesce()
        }
    }

    private suspend fun prepareStreamingHandle(snapshot: CurrentModelResult): Long {
        if (!snapshot.found) {
            throw SDKException.modelNotLoaded()
        }

        val model = snapshot.model
        val modelId = snapshot.model_id.ifEmpty { model?.id.orEmpty() }
        val modelName = model?.name?.ifEmpty { modelId } ?: modelId
        val modelPath = snapshot.resolved_path.ifEmpty { model?.local_path.orEmpty() }
        if (modelId.isEmpty() || modelPath.isEmpty()) {
            throw SDKException.modelLoadFailed(
                modelId = modelId,
                reason = "Loaded STT model is missing a resolved path",
            )
        }

        if (currentModelId == modelId) {
            return getHandle()
        }

        loadModel(
            modelPath = modelPath,
            modelId = modelId,
            modelName = modelName,
            framework = snapshot.framework.toCFramework(),
        )
        return getHandle()
    }

    private fun partialFromEvent(event: STTStreamEvent): STTPartialResult? =
        when (event.kind) {
            STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL,
            STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT,
            -> event.partial
            STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL -> {
                val basis = event.partial ?: STTPartialResult()
                basis.copy(
                    is_final = true,
                    final_output = event.final_output ?: basis.final_output,
                    text = basis.text.ifEmpty { event.final_output?.text.orEmpty() },
                )
            }
            STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR ->
                errorPartial(
                    event.error_message ?: "STT stream failed",
                    event.error_code,
                )
            STTStreamEventKind.STT_STREAM_EVENT_KIND_STARTED,
            STTStreamEventKind.STT_STREAM_EVENT_KIND_UNSPECIFIED,
            -> null
        }

    private fun errorPartial(message: String, code: Int): STTPartialResult =
        STTPartialResult(
            text = message,
            is_final = true,
            final_output = STTOutput(text = message, error_message = message, error_code = code),
        )

    private fun InferenceFramework.toCFramework(): Int =
        when (this) {
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> CppBridgeModelRegistry.Framework.ONNX
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> CppBridgeModelRegistry.Framework.LLAMACPP
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> CppBridgeModelRegistry.Framework.FOUNDATION_MODELS
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> CppBridgeModelRegistry.Framework.SYSTEM_TTS
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> CppBridgeModelRegistry.Framework.FLUID_AUDIO
            InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> CppBridgeModelRegistry.Framework.BUILTIN
            InferenceFramework.INFERENCE_FRAMEWORK_NONE -> CppBridgeModelRegistry.Framework.NONE
            InferenceFramework.INFERENCE_FRAMEWORK_MLX -> CppBridgeModelRegistry.Framework.MLX
            InferenceFramework.INFERENCE_FRAMEWORK_COREML -> CppBridgeModelRegistry.Framework.COREML
            InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> CppBridgeModelRegistry.Framework.METALRT
            InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> CppBridgeModelRegistry.Framework.GENIE
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> CppBridgeModelRegistry.Framework.SHERPA
            else -> CppBridgeModelRegistry.Framework.UNKNOWN
        }
}
