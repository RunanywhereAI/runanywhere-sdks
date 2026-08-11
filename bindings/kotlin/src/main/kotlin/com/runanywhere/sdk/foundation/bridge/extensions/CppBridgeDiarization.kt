/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeDiarization.kt
 *
 * Standalone speaker-diarization component bridge — wraps the proto-canonical
 * `rac_diarization_*` C ABI: one offline lifecycle verb plus the persistent
 * stream-session ABI (one callback registration per component handle, start
 * returns an opaque session id, feed accepts raw PCM chunks, stop drains /
 * finalizes, cancel suppresses later events).
 *
 * All generic scaffolding (handle creation, isLoaded, loadModel, unload,
 * destroy) lives in [ComponentActor]; this object only adds the
 * diarization-specific surfaces (`diarize`, `diarizeSessionStream`).
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+Diarization.swift`.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.DiarizationRequest
import ai.runanywhere.proto.v1.DiarizationResult
import ai.runanywhere.proto.v1.DiarizationStreamEvent
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RADiarizationOptions
import com.runanywhere.sdk.public.types.RADiarizationRequest
import com.runanywhere.sdk.public.types.RADiarizationResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

/**
 * Mirrors Swift `CppBridge.Diarization`. Wraps `rac_diarization_*` C ABI.
 * Handle lifecycle lives in [inner]; the offline verb is handle-free
 * (lifecycle-owned), matching the segmentation bridge.
 */
object CppBridgeDiarization {
    /** Generic scaffold (handle / isLoaded / loadModel / unload / destroy). */
    private val inner = ComponentActor(ComponentVTable.diarization)

    private val logger = SDKLogger("CppBridge.Diarization")

    // MARK: - Handle Management

    /** Get or create the diarization component handle. */
    suspend fun getHandle(): Long = inner.getHandle()

    /** Currently-loaded model id, or null. */
    val currentModelId: String?
        get() = inner.currentAssetId

    // MARK: - Model Lifecycle

    /** Unload the current model. */
    suspend fun unload() {
        inner.unload()
    }

    /** Destroy the component. */
    suspend fun destroy() {
        inner.destroy()
    }

    // MARK: - Offline diarization

    /**
     * One-shot diarization via the lifecycle-loaded speaker-diarization model.
     *
     * Mirrors iOS Swift's `CppBridge.Diarization.diarize(_:)` which serializes
     * an `RADiarizationRequest` and calls `rac_diarization_diarize_lifecycle_proto`.
     * The component handle is intentionally unused — the lifecycle is the source
     * of truth for "is a diarization model loaded".
     */
    suspend fun diarize(request: RADiarizationRequest): RADiarizationResult {
        val payload =
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhereBridge.racDiarizationDiarizeLifecycleProto(
                        DiarizationRequest.ADAPTER.encode(request),
                    )
                }
            } catch (error: SDKException) {
                throw error
            } catch (error: Throwable) {
                throw SDKException.operation(
                    "Speaker diarization failed: ${error.message ?: error::class.java.simpleName}",
                    error,
                )
            } ?: throw SDKException.operation(
                "racDiarizationDiarizeLifecycleProto returned null",
            )

        return try {
            DiarizationResult.ADAPTER.decode(payload)
        } catch (error: Exception) {
            throw SDKException.operation(
                "Failed to decode racDiarizationDiarizeLifecycleProto result: ${error.message}",
                error,
            )
        }
    }

    // MARK: - Streaming diarization

    /**
     * Persistent stream-in / event-out diarization.
     *
     * Mirrors Swift's `CppBridge.Diarization.stream`: prepare a component handle
     * for the lifecycle-loaded model, register one proto callback, start a
     * session, feed each incoming audio chunk as it arrives, then stop or cancel
     * the session depending on the collection outcome. Native emits canonical
     * [DiarizationStreamEvent] envelopes (STARTED / UPDATE / FINAL / ERROR);
     * Kotlin decodes and forwards them verbatim, terminating on FINAL / ERROR.
     */
    suspend fun diarizeSessionStream(
        audio: Flow<ByteArray>,
        options: RADiarizationOptions,
        loadedModel: CurrentModelResult,
        onEvent: (DiarizationStreamEvent) -> Boolean,
    ) {
        val handle = prepareStreamingHandle(loadedModel)
        var sessionId = 0L
        var shouldCancel = false

        val listener =
            NativeProtoProgressListener { bytes ->
                onEvent(DiarizationStreamEvent.ADAPTER.decode(bytes))
            }

        checkRc(
            RunAnywhereBridge.racDiarizationSetStreamProtoCallback(handle, listener),
            "racDiarizationSetStreamProtoCallback",
        )

        try {
            val started =
                RunAnywhereBridge.racDiarizationStreamStartProto(
                    handle,
                    RADiarizationOptions.ADAPTER.encode(options),
                )
            if (started <= 0L) {
                throw SDKException.operation("racDiarizationStreamStartProto failed with rc=$started")
            }
            sessionId = started

            audio.collect { chunk ->
                if (chunk.isEmpty()) return@collect
                val feedRc = RunAnywhereBridge.racDiarizationStreamFeedAudioProto(sessionId, chunk)
                if (feedRc != RunAnywhereBridge.RAC_SUCCESS) {
                    shouldCancel = true
                    throw SDKException.operation("racDiarizationStreamFeedAudioProto failed with rc=$feedRc")
                }
            }

            val stopRc = RunAnywhereBridge.racDiarizationStreamStopProto(sessionId)
            if (stopRc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("racDiarizationStreamStopProto failed with rc=$stopRc")
            }
        } catch (e: CancellationException) {
            shouldCancel = true
            throw e
        } catch (e: Throwable) {
            shouldCancel = true
            throw e
        } finally {
            if (shouldCancel && sessionId > 0L) {
                RunAnywhereBridge.racDiarizationStreamCancelProto(sessionId)
            }
            RunAnywhereBridge.racDiarizationUnsetStreamProtoCallback(handle)
            RunAnywhereBridge.racDiarizationProtoQuiesce()
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
                reason = "Loaded speaker-diarization model is missing a resolved path",
            )
        }

        if (currentModelId == modelId) {
            return getHandle()
        }

        inner.loadModel(path = modelPath, id = modelId, name = modelName)
        logger.info("Speaker-diarization streaming model loaded: $modelId")
        return getHandle()
    }

    private fun checkRc(rc: Int, operation: String) {
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation("$operation failed with rc=$rc")
        }
    }
}
