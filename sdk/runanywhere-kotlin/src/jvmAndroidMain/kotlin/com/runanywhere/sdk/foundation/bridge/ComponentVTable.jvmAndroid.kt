/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ComponentVTable.jvmAndroid.kt
 *
 * jvmAndroid actual for ComponentVTable. Wires the 5 vtable ops per
 * modality to the matching `rac_*_component_*` JNI primitives exposed
 * by `RunAnywhereBridge`.
 *
 * Mirrors Swift's static vtable instances in
 * `Sources/RunAnywhere/Foundation/Bridge/ComponentVTable.swift`
 * (extension on `CppBridge.ComponentVTable`).
 *
 * Notes on the current JNI surface (matches `rac_*_component.h` C ABI
 * deprecation in CPP_PROTO_OWNERSHIP.md):
 * - `create` / `destroy` map to the explicit `racXxxComponentCreate` /
 *   `racXxxComponentDestroy` JNI thunks.
 * - `isLoaded` is derived from the proto-canonical lifecycle snapshot
 *   (state == READY) to avoid a redundant JNI thunk and to match the
 *   migration direction documented in `rac_llm_component.h`
 *   ("delete after SDK migration — replaced by rac_model_lifecycle_*").
 * - `cleanup` routes through the canonical
 *   `rac_model_lifecycle_unload_proto` thunk for the matching component.
 * - `loadModel` routes through `rac_model_lifecycle_load_proto`. The
 *   request proto doesn't carry path/name directly — it resolves the
 *   model from the registry by `model_id` and framework, so the
 *   slot's `path`/`name` args are ignored at this layer. Mirrors
 *   Swift's `rac_*_component_load_{model,voice}` semantics through
 *   the proto-canonical path Kotlin already exposes.
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
public actual class ComponentVTable internal constructor(
    public actual val component: SDKComponent,
    private val createFn: () -> Long,
    private val destroyFn: (Long) -> Unit,
    public actual val loadModel: ((handle: Long, path: String, id: String, name: String) -> Int)?,
) {
    public actual fun create(): Long = createFn()

    public actual fun destroy(handle: Long) = destroyFn(handle)

    /**
     * Proto-canonical readiness check. Returns true iff the lifecycle
     * snapshot reports `COMPONENT_LIFECYCLE_STATE_READY` (the only state
     * indicating an active, usable, loaded asset). Falls back to
     * `false` if the snapshot is unavailable, matching Swift's
     * `rac_*_component_is_loaded` semantics.
     */
    public actual fun isLoaded(handle: Long): Boolean {
        val snapshot: ComponentLifecycleSnapshot =
            CppBridgeModelLifecycle.snapshot(component) ?: return false
        return snapshot.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
    }

    /**
     * Cleanup via the canonical proto unload path. Best-effort —
     * mirrors Swift where `rac_*_component_cleanup` errors are
     * intentionally discarded (the cleanup is fire-and-forget).
     */
    public actual fun cleanup(handle: Long) {
        CppBridgeModelLifecycle.unload(
            ModelUnloadRequest(unload_all = true),
        )
    }

    public actual companion object {
        public actual val llm: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_LLM,
                createFn = { RunAnywhereBridge.racLlmComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racLlmComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public actual val stt: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_STT,
                createFn = { RunAnywhereBridge.racSttComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racSttComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public actual val tts: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_TTS,
                createFn = { RunAnywhereBridge.racTtsComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racTtsComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public actual val vad: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_VAD,
                createFn = { RunAnywhereBridge.racVadComponentCreate() },
                destroyFn = { handle -> RunAnywhereBridge.racVadComponentDestroy(handle) },
                loadModel = { _, _, id, _ -> loadViaLifecycle(id) },
            )

        public actual val vlm: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_VLM,
                // VLM in the Kotlin SDK never owns a bare component handle
                // (load+create are fused at the proto service layer).
                // Mirrors Swift Wave 7 / T23 note: the slot is kept for
                // shape uniformity but is dead in practice.
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
         * Returns RAC_SUCCESS on success or RAC_ERROR_OPERATION_FAILED
         * otherwise.
         */
        private fun loadViaLifecycle(modelId: String): Int {
            val result =
                CppBridgeModelLifecycle.load(
                    ModelLoadRequest(model_id = modelId),
                ) ?: return RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
            return if (result.success) {
                RunAnywhereBridge.RAC_SUCCESS
            } else {
                RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
            }
        }
    }
}
