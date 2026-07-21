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

import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * jvmAndroid actual. See the commonMain `expect` declaration for the
 * shared contract.
 */
public class ComponentVTable internal constructor(
    public val component: SDKComponent,
    private val createFn: () -> Long,
    private val isLoadedFn: (Long) -> Boolean,
    private val destroyFn: (Long) -> Unit,
    private val cleanupFn: (Long) -> Int,
    public val loadModel: ((handle: Long, path: String, id: String, name: String) -> Int)?,
) {
    public fun create(): Long = createFn()

    public fun destroy(handle: Long) = destroyFn(handle)

    public fun isLoaded(handle: Long): Boolean = isLoadedFn(handle)

    public fun cleanup(handle: Long) {
        cleanupFn(handle)
    }

    public companion object {
        public val llm: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_LLM,
                createFn = { RunAnywhereBridge.racLlmComponentCreate() },
                isLoadedFn = { handle -> RunAnywhereBridge.racLlmComponentIsLoaded(handle) },
                destroyFn = { handle -> RunAnywhereBridge.racLlmComponentDestroy(handle) },
                cleanupFn = { handle -> RunAnywhereBridge.racLlmComponentCleanup(handle) },
                loadModel = { handle, path, id, name -> RunAnywhereBridge.racLlmComponentLoadModel(handle, path, id, name) },
            )

        public val stt: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_STT,
                createFn = { RunAnywhereBridge.racSttComponentCreate() },
                isLoadedFn = { handle -> RunAnywhereBridge.racSttComponentIsLoaded(handle) },
                destroyFn = { handle -> RunAnywhereBridge.racSttComponentDestroy(handle) },
                cleanupFn = { handle -> RunAnywhereBridge.racSttComponentCleanup(handle) },
                loadModel = { handle, path, id, name -> RunAnywhereBridge.racSttComponentLoadModel(handle, path, id, name) },
            )

        public val tts: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_TTS,
                createFn = { RunAnywhereBridge.racTtsComponentCreate() },
                isLoadedFn = { handle -> RunAnywhereBridge.racTtsComponentIsLoaded(handle) },
                destroyFn = { handle -> RunAnywhereBridge.racTtsComponentDestroy(handle) },
                cleanupFn = { handle -> RunAnywhereBridge.racTtsComponentCleanup(handle) },
                loadModel = { handle, path, id, name -> RunAnywhereBridge.racTtsComponentLoadVoice(handle, path, id, name) },
            )

        public val vad: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_VAD,
                createFn = { RunAnywhereBridge.racVadComponentCreate() },
                isLoadedFn = { handle -> RunAnywhereBridge.racVadComponentIsLoaded(handle) },
                destroyFn = { handle -> RunAnywhereBridge.racVadComponentDestroy(handle) },
                cleanupFn = { handle -> RunAnywhereBridge.racVadComponentCleanup(handle) },
                loadModel = { handle, path, id, name -> RunAnywhereBridge.racVadComponentLoadModel(handle, path, id, name) },
            )

        // Standalone speaker-diarization component vtable. Mirrors Swift's
        // `ComponentVTable.diarization`, whose `cleanup` maps to
        // `rac_diarization_component_unload` (no separate `_cleanup` C ABI).
        public val diarization: ComponentVTable =
            ComponentVTable(
                component = SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION,
                createFn = { RunAnywhereBridge.racDiarizationComponentCreate() },
                isLoadedFn = { handle -> RunAnywhereBridge.racDiarizationComponentIsLoaded(handle) },
                destroyFn = { handle -> RunAnywhereBridge.racDiarizationComponentDestroy(handle) },
                cleanupFn = { handle -> RunAnywhereBridge.racDiarizationComponentUnload(handle) },
                loadModel = { handle, path, id, name -> RunAnywhereBridge.racDiarizationComponentLoadModel(handle, path, id, name) },
            )
    }
}
