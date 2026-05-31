/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ComponentVTable.kt
 *
 * Per-modality vtable describing the 5 ops that vary across the
 * LLM / STT / TTS / VAD / VLM component actor scaffolds. The rest of
 * the actor (handle caching, error wrapping, lifecycle gates) is
 * generic and will live in a shared ComponentActor scaffold (Kotlin
 * counterpart of Swift's CppBridge.ComponentActor) introduced in
 * subsequent waves.
 *
 * VoiceAgent is intentionally NOT modeled here — its handle type wraps
 * a composite (STT + LLM + TTS + VAD) and create() is async. VoiceAgent
 * keeps its own bespoke scaffold (mirrors Swift's exception).
 *
 * Kotlin SDK mirror of Swift's
 * `Sources/RunAnywhere/Foundation/Bridge/ComponentVTable.swift`.
 * Design (Option A): expect/class with a companion object that
 * exposes the 5 modality instances (`llm`, `stt`, `tts`, `vad`, `vlm`).
 * Platform implementations wire to RunAnywhereBridge JNI primitives.
 */

package com.runanywhere.sdk.foundation.bridge

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * jvmAndroid actual. See the commonMain `expect` declaration for the
 * shared contract.
 */
public class ComponentVTable internal constructor(
    public val component: SDKComponent,
    private val createFn: () -> Long,
    private val destroyFn: (Long) -> Unit,
    public val loadModel: ((handle: Long, path: String, id: String, name: String) -> Int)?,
) {
    public fun create(): Long = createFn()

    public fun destroy(handle: Long) = destroyFn(handle)

    /**
     * Proto-canonical readiness check. Returns true iff the lifecycle
     * snapshot reports `COMPONENT_LIFECYCLE_STATE_READY` (the only state
     * indicating an active, usable, loaded asset). Falls back to
     * `false` if the snapshot is unavailable, matching Swift's
     * `rac_*_component_is_loaded` semantics. `handle` is part of the
     * vtable contract (parity with Swift's `rac_*_component_is_loaded`
     * C ABI) but the proto-canonical readiness check routes through
     * the lifecycle snapshot, which is keyed by component.
     */
    @Suppress("UnusedParameter")
    public fun isLoaded(handle: Long): Boolean {
        val snapshot: ComponentLifecycleSnapshot =
            CppBridgeModelLifecycle.snapshot(component) ?: return false
        return snapshot.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
    }

    /**
     * Cleanup via the canonical proto unload path. Best-effort —
     * mirrors Swift where `rac_*_component_cleanup` errors are
     * intentionally discarded (the cleanup is fire-and-forget).
     * `handle` is part of the vtable contract (parity with Swift's
     * `rac_*_component_cleanup` C ABI) but the unload routes through
     * the lifecycle, which is keyed by component.
     */
    @Suppress("UnusedParameter")
    public fun cleanup(handle: Long) {
        CppBridgeModelLifecycle.unload(
            ModelUnloadRequest(unload_all = true),
        )
    }

    public companion object {
        public val llm: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_LLM,
                createFn = { RunAnywhereBridge.racLlmComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racLlmComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public val stt: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_STT,
                createFn = { RunAnywhereBridge.racSttComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racSttComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public val tts: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_TTS,
                createFn = { RunAnywhereBridge.racTtsComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racTtsComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public val vad: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_VAD,
                createFn = { RunAnywhereBridge.racVadComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racVadComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public val vlm: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_VLM,
                // VLM in the Kotlin SDK never owns a bare component handle
                // (load+create are fused at the proto service layer).
                // The slot is kept for shape uniformity but is dead in practice.
                createFn = { 0L },
                destroyFn = { handle -> RunAnywhereBridge.racVlmDestroy(handle) },
                // Slot kept for shape uniformity.
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        /**
         * Shared helper that funnels every modality's `loadModel` slot
         * through the canonical `rac_model_lifecycle_load_proto`. The
         * registry resolves path/framework/category from the
         * `model_id`, so callers only need to supply the id here.
         * Returns RAC_SUCCESS on success or RAC_ERROR_MODEL_LOAD_FAILED
         * otherwise.
         */
        private fun loadViaLifecycle(modelId: String): Int {
            val result =
                CppBridgeModelLifecycle.load(
                    ModelLoadRequest(model_id = modelId),
                ) ?: return RunAnywhereBridge.RAC_ERROR_MODEL_LOAD_FAILED
            return if (result.success) {
                RunAnywhereBridge.RAC_SUCCESS
            } else {
                RunAnywhereBridge.RAC_ERROR_MODEL_LOAD_FAILED
            }
        }
    }
}
