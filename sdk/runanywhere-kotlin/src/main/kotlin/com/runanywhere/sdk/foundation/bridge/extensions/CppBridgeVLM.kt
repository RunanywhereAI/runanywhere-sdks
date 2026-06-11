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
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
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
     * (see `rac_vlm_process_stream_proto` / `RunAnywhereBridge` comments).
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

    /**
     * Check if streaming is supported by the loaded VLM component.
     *
     * Mirrors Swift `CppBridge.VLM.supportsStreaming` — exposes the
     * `rac_vlm_component_supports_streaming` introspection helper through
     * the JNI thunk. Returns false when no component handle exists.
     */
    suspend fun supportsStreaming(): Boolean {
        val h = actor.existingHandle() ?: return false
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
        val h = actor.existingHandle() ?: return RunAnywhereBridge.RAC_LIFECYCLE_IDLE
        return RunAnywhereBridge.racVlmComponentGetState(h)
    }

    suspend fun process(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
    ): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessProto(
                getHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
            ),
            "racVlmProcessProto",
        )

    /**
     * Stream VLM output as canonical [SDKEvent] envelopes.
     *
     * Mirrors Swift `CppBridge.VLM.processStream` — the native call delivers
     * token events through the callback; the aggregate [VLMResult] returned
     * by the C ABI is validated but not forwarded to callers (public API is
     * event-driven via [RunAnywhere.processImageStream]).
     */
    suspend fun processStream(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (SDKEvent) -> Boolean,
    ): RAVLMResult {
        val handle = getHandle()
        return decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessStreamProto(
                handle,
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    try {
                        // `rac_vlm_process_stream_proto` emits canonical SDKEvent
                        // envelopes (per-token TOKEN_GENERATED + terminal
                        // STREAM_COMPLETED — vlm_module.cpp stream_token_trampoline).
                        // Decode SDKEvent directly: trying VLMStreamEvent first
                        // mis-decodes these bytes (proto skips unknown fields,
                        // kind stays UNSPECIFIED) and every event gets dropped.
                        onEvent(SDKEvent.ADAPTER.decode(bytes))
                    } catch (e: Exception) {
                        logger.warning("Failed to decode VLM stream event: ${e.message}")
                        true
                    }
                },
            ),
            "racVlmProcessStreamProto",
        )
    }
}
