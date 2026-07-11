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
 * inference helpers route through the lifecycle whenever it is loaded.
 * The vtable's `createFn` returns 0L by
 * design (see `ComponentVTable.jvmAndroid.kt`), so `getHandle()` on the
 * actor is intentionally non-functional; callers pass handle `0L` into
 * the proto ABI and commons acquires the lifecycle-owned VLM service.
 *
 * VLM-specific surfaces kept here (mirrors Swift's slim
 * CppBridge+VLM.swift):
 *   - [cancel] — routes through `rac_vlm_cancel_lifecycle_proto` (no
 *     handle threaded), with a handle-based fallback for the transition
 *     window while the commons JNI symbol is being wired up.
 *   - [process] / [processStream] — proto-canonical inference helpers
 *     that thread the actor handle (0L) into the C ABI for signature
 *     parity with Swift.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VLM.swift`.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMGenerationRequest
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
import ai.runanywhere.proto.v1.VLMStreamEvent
import ai.runanywhere.proto.v1.VLMStreamEventKind
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
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
    val payload =
        bytes ?: throw SDKException.operation("$operation returned null (no native error detail)")
    return try {
        adapter.decode(payload)
    } catch (e: Exception) {
        throw SDKException.operation("Failed to decode $operation result: ${e.message}", e)
    }
}

internal data class NativeVLMProcessRequest(
    val imageProto: ByteArray,
    val optionsProto: ByteArray,
)

internal data class NativeVLMStreamRequest(
    val requestProto: ByteArray,
    val listener: NativeProtoProgressListener,
)

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
     * Proto ABI handle for VLM inference. Mirrors Swift's `getHandle()` surface
     * but returns `0L` because Kotlin has no `rac_vlm_component_create` JNI
     * binding yet — commons/JNI treat handle `0` as "use lifecycle-owned VLM"
     * (see `rac_vlm_process_proto` / `RunAnywhereBridge` comments).
     * Do not route through [ComponentActor.getHandle]: the VLM vtable
     * `createFn` returns `0L` by design and the actor rejects that as failure.
     */
    @Suppress("FunctionOnlyReturningConstant")
    suspend fun getHandle(): Long = 0L

    suspend fun destroy() {
        actor.destroy()
    }

    /**
     * Cancel ongoing generation via the lifecycle cancel proto.
     *
     * Replaces the legacy handle-based `rac_vlm_component_cancel` path.
     * The lifecycle ABI acquires the lifecycle-owned
     * VLM service internally, dispatches `cancel` on its vtable, and
     * emits canonical `CANCELLATION_EVENT_KIND_*` SDKEvents — keeping
     * the cancel path consistent with LLM cancellation semantics.
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
            logger.warning("VLM cancel skipped: lifecycle cancel JNI unavailable")
        } catch (e: Exception) {
            logger.warning("VLM cancel skipped: ${e.message}")
        }
    }

    /** Cancel only the matching request-scoped JNI wrapper. */
    internal fun cancelRequest(requestId: Long) {
        val bytes = RunAnywhereBridge.racVlmCancelRequestLifecycleProto(requestId)
        if (bytes != null) {
            // Decode the canonical cancellation event for parity with the
            // unscoped surface; publishing is owned by commons.
            SDKEvent.ADAPTER.decode(bytes)
        }
    }

    /**
     * Check if streaming is supported by the loaded VLM component.
     *
     * Mirrors Swift `CppBridge.VLM.supportsStreaming` — exposes the
     * `rac_vlm_component_supports_streaming` introspection helper through
     * the JNI thunk. Returns false when no component handle exists.
     */
    suspend fun supportsStreaming(): Boolean {
        val h = actor.existingHandle()
        if (h == 0L) return false
        return RunAnywhereBridge.racVlmComponentSupportsStreaming(h)
    }

    /**
     * Get the current lifecycle state of the loaded VLM component.
     *
     * Mirrors Swift `CppBridge.VLM.state` — exposes the
     * `rac_vlm_component_get_state` introspection helper through the JNI
     * thunk. Return value is a `rac_lifecycle_state_t` int.
     */
    suspend fun state(): Int {
        val h = actor.existingHandle()
        if (h == 0L) return RunAnywhereBridge.RAC_LIFECYCLE_IDLE
        return RunAnywhereBridge.racVlmComponentGetState(h)
    }

    suspend fun process(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
    ): RAVLMResult = processBlocking(image, options)

    /** Blocking JNI implementation; public coroutine APIs own dispatch/cancel. */
    internal fun processBlocking(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
    ): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessProto(
                0L,
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
            ),
            "racVlmProcessProto",
        )

    /** Encode before cancellable admission so JNI is the next throwing boundary. */
    internal fun prepareProcessRequest(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
    ): NativeVLMProcessRequest =
        NativeVLMProcessRequest(
            imageProto = VLMImage.ADAPTER.encode(image),
            optionsProto = VLMGenerationOptions.ADAPTER.encode(options),
        )

    /** Request-scoped blocking JNI implementation for cancellable public APIs. */
    internal fun processRequestBlocking(
        requestId: Long,
        request: NativeVLMProcessRequest,
    ): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessRequestProto(
                requestId,
                0L,
                request.imageProto,
                request.optionsProto,
            ),
            "racVlmProcessRequestProto",
        )

    /**
     * Stream typed [VLMStreamEvent]s from the lifecycle-owned VLM model.
     *
     * Mirrors Swift `CppBridge.VLM.processStream` over the canonical typed
     * ABI (`rac_vlm_stream_proto`): serialized `VLMGenerationRequest` in,
     * one `VLMStreamEvent` per callback (STARTED → TOKEN* → exactly one
     * terminal COMPLETED/ERROR; COMPLETED carries the full [VLMResult]).
     * `model_id` is left unset — commons resolves the lifecycle-owned model
     * and only validates the field when non-empty.
     *
     * [onEvent] returns false to stop the native stream (consumer cancel).
     */
    suspend fun processStream(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (VLMStreamEvent) -> Boolean,
    ) = processStreamBlocking(image, options, onEvent)

    /** Blocking JNI implementation; public coroutine APIs own dispatch/cancel. */
    internal fun processStreamBlocking(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (VLMStreamEvent) -> Boolean,
    ) {
        val request = prepareStreamRequest(image, options, onEvent)
        val rc = RunAnywhereBridge.racVlmStreamProto(request.requestProto, request.listener)
        throwIfStreamFailed("rac_vlm_stream_proto", rc)
    }

    /** Encode and allocate the listener before cancellable JNI admission. */
    internal fun prepareStreamRequest(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (VLMStreamEvent) -> Boolean,
    ): NativeVLMStreamRequest {
        val request =
            VLMGenerationRequest(
                images = listOf(image),
                options = options.copy(streaming_enabled = true),
            )
        val requestBytes = VLMGenerationRequest.ADAPTER.encode(request)
        val listener =
            NativeProtoProgressListener { bytes ->
                try {
                    val event = VLMStreamEvent.ADAPTER.decode(bytes)
                    onEvent(event) && shouldContinueNativeStream(event)
                } catch (e: SDKException) {
                    throw e
                } catch (e: Exception) {
                    logger.warning("Failed to decode VLM stream event: ${e.message}")
                    true
                }
            }
        return NativeVLMStreamRequest(requestBytes, listener)
    }

    /** Request-scoped stream JNI implementation for cancellable public APIs. */
    internal fun processStreamRequestBlocking(
        requestId: Long,
        request: NativeVLMStreamRequest,
    ) {
        val rc = RunAnywhereBridge.racVlmStreamRequestProto(requestId, request.requestProto, request.listener)
        throwIfStreamFailed("racVlmStreamRequestProto", rc)
    }

    private fun throwIfStreamFailed(
        operation: String,
        rc: Int,
    ) {
        if (rc != 0) {
            throw SDKException.vlm("$operation failed: rc=$rc")
        }
    }

    /**
     * Native-stream continuation policy: stop after the terminal
     * COMPLETED/ERROR event (or any event flagged `is_final`).
     */
    private fun shouldContinueNativeStream(event: VLMStreamEvent): Boolean =
        when (event.kind) {
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED,
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR,
            -> false
            else -> !event.is_final
        }
}
