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
 * Kotlin SDK W2-1 mirror of Swift's
 * `Sources/RunAnywhere/Foundation/Bridge/ComponentVTable.swift`.
 * Design (Option A): expect/actual class with a companion object that
 * exposes the 5 modality instances (`llm`, `stt`, `tts`, `vad`, `vlm`).
 * Platform implementations wire to RunAnywhereBridge JNI primitives.
 */

package com.runanywhere.sdk.foundation.bridge

import ai.runanywhere.proto.v1.SDKComponent

/**
 * Function-pointer table parameterizing one modality's component actor.
 *
 * Five ops vary per modality; the actor scaffold (lazy create,
 * `isLoaded`, `loadModel`, `cleanup`, `destroy`) is shared.
 *
 * Mirrors Swift's `CppBridge.ComponentVTable` exactly: identity +
 * 5 lifecycle ops (the 5th — `loadModel` — is optional).
 */
public expect class ComponentVTable {
    /**
     * The proto-canonical component identity. Used for log/error labels
     * and for keying lifecycle state across components.
     */
    public val component: SDKComponent

    /**
     * Create the C++ component, returning the new opaque handle.
     * Returns 0L on failure.
     */
    public fun create(): Long

    /**
     * Query whether the component has a model/voice currently loaded.
     */
    public fun isLoaded(handle: Long): Boolean

    /**
     * Cleanup (unload) the loaded asset, leaving the component reusable.
     */
    public fun cleanup(handle: Long)

    /**
     * Destroy the underlying C++ component and release its resources.
     */
    public fun destroy(handle: Long)

    /**
     * Load a model/voice given (path, id, name). May be null when the
     * modality has no path-based load — matches Swift's `Optional`
     * `loadModel` slot so VLM (extra projector path) can opt out
     * without adding a third arg shape here. Returns `rac_result_t`
     * (0 == success).
     */
    public val loadModel: ((handle: Long, path: String, id: String, name: String) -> Int)?

    public companion object {
        /** LLM component vtable — `rac_llm_component_*` family. */
        public val llm: ComponentVTable

        /** STT component vtable — `rac_stt_component_*` family. */
        public val stt: ComponentVTable

        /**
         * TTS component vtable — `rac_tts_component_*` family.
         * The "model" generic name aliases TTS's "voice" terminology at the C ABI.
         */
        public val tts: ComponentVTable

        /** VAD component vtable — `rac_vad_component_*` family. */
        public val vad: ComponentVTable

        /**
         * VLM component vtable — `rac_vlm_component_*` family.
         *
         * Mirrors Swift Wave 7 / T23: the level-3 handle is never loaded
         * with a model and the `loadModel` slot is dead in practice. The
         * slot is kept here only so the `ComponentVTable` shape stays
         * uniform with the sibling modalities (LLM, STT, TTS, VAD).
         * Inference and cancel route through the lifecycle service via
         * the proto ABI.
         */
        public val vlm: ComponentVTable
    }
}
