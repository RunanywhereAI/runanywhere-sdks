/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeVLM.kt
 *
 * VLM component bridge — manages the C++ VLM proto-canonical surface
 * (`rac_vlm_*_proto` C ABI).
 *
 * Generic scaffolding (handle / destroy / closure) lives in
 * [ComponentActor]. The VLM actor exists only to host a per-process
 * scaffold that mirrors the sibling modalities (LLM / STT / TTS / VAD)
 * for shape uniformity — the canonical VLM model state is owned by the
 * C++ lifecycle (`rac_model_lifecycle_load_proto`), and the proto
 * inference helpers route through the lifecycle whenever it is loaded
 * (Phase 6j / Wave 7 / T23). The vtable's `createFn` returns 0L by
 * design (see `ComponentVTable.jvmAndroid.kt`), so `getHandle()` on the
 * actor is intentionally non-functional; consumers acquire the inference
 * handle via [loadResolvedArtifacts] until the Kotlin commons JNI
 * exposes the parameterless lifecycle process/stream variants (W3-5
 * follow-up).
 *
 * VLM-specific surfaces kept here (mirrors Swift's slim post-Wave-7
 * CppBridge+VLM.swift):
 *   - [cancel] — routes through `rac_vlm_cancel_lifecycle_proto` (no
 *     handle threaded), with a handle-based fallback for the transition
 *     window while the commons JNI symbol is being wired up.
 *   - [process] / [processStream] — proto-canonical inference helpers
 *     that thread the load-time handle into the proto ABI.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VLM.swift`.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsRequest
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsResponse
import ai.runanywhere.proto.v1.VLMResult
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASDKEvent
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
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

/**
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VLM.swift`. Wraps `rac_vlm_*_proto` C ABI.
 */
object CppBridgeVLM {
    /**
     * Generic scaffold (closure / destroy). VLM's vtable `createFn`
     * returns 0L so the actor never holds a level-3 handle — the slot
     * is kept for parity with the sibling modalities and to share the
     * shutdown semantics that the actor provides.
     */
    internal val actor = ComponentActor(ComponentVTable.vlm)

    private val logger = SDKLogger("CppBridge.VLM")

    /**
     * Load-time handle returned by `racVlmComponentLoadResolvedArtifactsProto`.
     * Owned by the lifecycle-orchestrated load path until [destroy]; the
     * proto inference helpers thread it into the C ABI to satisfy the
     * `rac_handle_t` parameter. Mirrors Swift's level-3 handle slot in
     * shape, even though Kotlin still drives the handle through the
     * load proto until the commons JNI exposes the parameterless
     * lifecycle process variants.
     */
    @Volatile private var handle: Long = 0L

    @Synchronized
    fun loadResolvedArtifacts(
        modelId: String,
        primaryModelPath: String,
        visionProjectorPath: String,
    ): Int {
        destroy()
        val request =
            VLMLoadResolvedArtifactsRequest(
                model_id = modelId,
                primary_model_path = primaryModelPath,
                mmproj_path = visionProjectorPath.takeIf { it.isNotBlank() },
            )
        val response =
            decodeOrThrow(
                VLMLoadResolvedArtifactsResponse.ADAPTER,
                RunAnywhereBridge.racVlmComponentLoadResolvedArtifactsProto(
                    VLMLoadResolvedArtifactsRequest.ADAPTER.encode(request),
                ),
                "racVlmComponentLoadResolvedArtifactsProto",
            )
        if (response.result_code != RunAnywhereBridge.RAC_SUCCESS || response.handle == 0L) {
            return if (response.result_code != RunAnywhereBridge.RAC_SUCCESS) {
                response.result_code
            } else {
                RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
            }
        }
        handle = response.handle
        return RunAnywhereBridge.RAC_SUCCESS
    }

    @Synchronized
    fun destroy() {
        if (handle != 0L) RunAnywhereBridge.racVlmDestroy(handle)
        handle = 0L
    }

    fun isLoaded(): Boolean = handle != 0L

    /**
     * Cancel ongoing generation via the lifecycle cancel proto.
     *
     * Replaces the legacy handle-based `rac_vlm_component_cancel` path
     * (Wave 7 / T23). The lifecycle ABI acquires the lifecycle-owned
     * VLM service internally, dispatches `cancel` on its vtable, and
     * emits canonical `CANCELLATION_EVENT_KIND_*` SDKEvents — keeping
     * the cancel path consistent with LLM cancellation semantics.
     *
     * When the commons JNI binding for `rac_vlm_cancel_lifecycle_proto`
     * is not yet present, falls back to the handle-based
     * `rac_vlm_cancel_proto` path so cancel keeps working through the
     * transition window.
     */
    fun cancel() {
        try {
            val bytes = RunAnywhereBridge.racVlmCancelLifecycleProto()
            if (bytes != null) {
                // Surface event for parity with Swift; not consumed by Kotlin callers today.
                SDKEvent.ADAPTER.decode(bytes)
            } else {
                logger.warning("VLM cancel skipped: no lifecycle VLM loaded")
            }
        } catch (_: UnsatisfiedLinkError) {
            // Commons JNI binding pending. Fall back to handle-based cancel.
            val h = handle
            if (h != 0L) RunAnywhereBridge.racVlmCancelProto(h)
        } catch (e: Exception) {
            logger.warning("VLM cancel skipped: ${e.message}")
        }
    }

    fun process(image: RAVLMImage, options: RAVLMGenerationOptions): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
            ),
            "racVlmProcessProto",
        )

    fun processStream(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (RASDKEvent) -> Boolean,
    ): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessStreamProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onEvent(SDKEvent.ADAPTER.decode(bytes))
                },
            ),
            "racVlmProcessStreamProto",
        )

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("VLM service not loaded")
}
