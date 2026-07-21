/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ComponentActor.kt
 *
 * Generic component-actor scaffold for a single C++ component (LLM / STT /
 * TTS / VAD / VLM). The variable parts are supplied via [ComponentVTable];
 * this type owns the rest:
 *
 *   - lazy handle creation (one C handle per component instance)
 *   - `isLoaded` proxy across the C ABI
 *   - `loadModel(...)` taking 3 strings, threaded through the vtable slot
 *   - `unload()` (cleanup) and `destroy()`
 *   - kotlinx.coroutines.sync.Mutex provides concurrency safety (Kotlin
 *     does not have a stable actor primitive)
 *   - structured logging keyed by the proto component name
 *
 * VoiceAgent does NOT use this scaffold — its handle type wraps a
 * composite (STT + LLM + TTS + VAD) and create() is async + composite.
 *
 * Kotlin SDK W2-2 mirror of Swift's
 * `Sources/RunAnywhere/Foundation/Bridge/ComponentActor.swift`.
 */

package com.runanywhere.sdk.foundation.bridge

import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Generic component actor: holds one opaque C++ handle and routes all
 * calls through a [ComponentVTable].
 *
 * Each modality wraps this in a typealias / facade actor that exposes
 * the modality-specific extras (cancel/stop/streaming flags,
 * lifecycle-result loaders, etc.) on top of the shared scaffold.
 *
 * Concurrency safety is provided by an internal coroutine [Mutex].
 * All state-mutating ops are `suspend` and serialize through the mutex,
 * mirroring Swift's `actor` isolation guarantees.
 */
public class ComponentActor(
    /** The vtable describing the wrapped C++ component. */
    public val vtable: ComponentVTable,
) {
    // MARK: - State

    private val mutex = Mutex()

    /**
     * Opaque C handle — 0L until first [getHandle] succeeds, and 0L
     * again after [destroy]. Reads outside the mutex are best-effort
     * snapshots (used by property accessors that mirror Swift's
     * actor-isolated `var` reads).
     */
    @Volatile
    private var handle: Long = 0L

    /**
     * Currently-loaded model/voice id (the "loaded asset id" — TTS
     * calls it a voice id, others call it a model id; the actor is
     * agnostic). Cleared on [unload] and [destroy].
     */
    @Volatile
    private var loadedAssetId: String? = null

    /**
     * Once true, the actor has been destroyed and is no longer usable;
     * further [getHandle] calls throw.
     */
    @Volatile
    private var closed: Boolean = false

    private val logger: SDKLogger = SDKLogger("CppBridge.${vtable.component.label}")

    // MARK: - Handle Management

    /**
     * Get or lazily create the underlying C handle.
     *
     * Throws [SDKException] if the actor is already shut down or if the
     * native create call fails.
     */
    public suspend fun getHandle(): Long = mutex.withLock { getOrCreateHandleLocked() }

    /**
     * Mutex-must-be-held variant of [getHandle]. Used by [loadModel] to
     * keep the entire `create + native load + loadedAssetId update`
     * sequence inside one critical section, so `unload()` / `destroy()`
     * cannot interleave with an in-flight model load (Swift parity:
     * Swift's `actor` isolates this naturally; Kotlin's `Mutex` is not
     * reentrant so we extract the locked body into a private helper).
     */
    private fun getOrCreateHandleLocked(): Long {
        if (handle != 0L) return handle
        if (closed) {
            throw SDKException.notInitialized("${vtable.component.label} component is shut down")
        }
        val newHandle = vtable.create()
        if (newHandle == 0L) {
            throw SDKException.notInitialized(
                "Failed to create ${vtable.component.label} component",
            )
        }
        handle = newHandle
        logger.debug("${vtable.component.label} component created")
        return newHandle
    }

    // MARK: - State queries

    /**
     * Whether the component currently has a model/voice loaded.
     *
     * Best-effort snapshot read (mirrors Swift's `var isLoaded: Bool`
     * computed property under actor isolation).
     */
    public val isLoaded: Boolean
        get() {
            val h = handle
            if (h == 0L) return false
            return vtable.isLoaded(h)
        }

    /**
     * Currently-loaded asset id (model id, voice id, …). `null` if no
     * asset is loaded.
     */
    public val currentAssetId: String?
        get() = loadedAssetId

    /**
     * Whether [destroy] has already been called. Used by callers that
     * want to skip re-init after shutdown.
     */
    public val isShutDown: Boolean
        get() = closed

    /**
     * Read-only access to the raw handle without triggering creation.
     * Returns 0L if the handle has not been created yet (or has been
     * destroyed).
     */
    public suspend fun existingHandle(): Long = mutex.withLock { handle }

    // MARK: - Lifecycle

    /**
     * Load a model/voice given `(path, id, name)`. Throws if the vtable
     * has no `loadModel` slot (e.g. modalities with non-standard load
     * signatures).
     */
    public suspend fun loadModel(
        path: String,
        id: String,
        name: String,
    ) {
        val load =
            vtable.loadModel
                ?: throw SDKException.notImplemented(
                    "${vtable.component.label} does not support generic loadModel",
                )
        // One serialized critical section: get-or-create the handle,
        // run the native load, and publish loadedAssetId atomically so
        // a concurrent unload()/destroy() cannot interleave with the
        // in-flight native call (which would leave the asset id set
        // for a freed handle). Mirrors Swift `ComponentActor.loadModel`
        // (Sources/RunAnywhere/Foundation/Bridge/ComponentActor.swift)
        // which runs the equivalent block under actor isolation.
        mutex.withLock {
            val h = getOrCreateHandleLocked()
            val status = load(h, path, id, name)
            if (status != 0) {
                throw SDKException.modelLoadFailed(
                    modelId = id,
                    reason = "${vtable.component.label} model load failed: rc=$status",
                )
            }
            loadedAssetId = id
            logger.info("${vtable.component.label} model loaded: $id")
        }
    }

    /**
     * Update the locally-tracked loaded asset id without touching the
     * C side. Used by modality-specific load paths that bypass this
     * scaffold's [loadModel] (e.g. modalities with non-standard load
     * signatures). Currently only VAD calls this to clear the asset id
     * on unload. Serialized through the actor mutex so it cannot race
     * with [loadModel] / [unload] / [destroy].
     */
    public suspend fun markAssetLoaded(id: String?) {
        mutex.withLock { loadedAssetId = id }
    }

    /**
     * Unload the currently-loaded model/voice. Safe to call when
     * nothing is loaded or the handle hasn't been created.
     */
    public suspend fun unload() =
        mutex.withLock {
            val h = handle
            if (h == 0L) return@withLock
            vtable.cleanup(h)
            loadedAssetId = null
            logger.info("${vtable.component.label} model unloaded")
        }

    /**
     * Destroy the component, releasing C resources and marking the
     * actor closed. Subsequent [getHandle] calls throw.
     */
    public suspend fun destroy() =
        mutex.withLock {
            val h = handle
            if (h != 0L) {
                vtable.destroy(h)
                logger.debug("${vtable.component.label} component destroyed")
            }
            handle = 0L
            loadedAssetId = null
            closed = true
        }
}

// MARK: - Label helper

/**
 * Short human-friendly label used in log categories and error
 * messages. Mirrors Swift's `private extension RASDKComponent.label`.
 * Avoids depending on the proto-generated `name` which carries the
 * verbose `SDK_COMPONENT_*` prefix.
 */
private val SDKComponent.label: String
    get() =
        when (this) {
            SDKComponent.SDK_COMPONENT_LLM -> "LLM"
            SDKComponent.SDK_COMPONENT_STT -> "STT"
            SDKComponent.SDK_COMPONENT_TTS -> "TTS"
            SDKComponent.SDK_COMPONENT_VAD -> "VAD"
            SDKComponent.SDK_COMPONENT_VLM -> "VLM"
            SDKComponent.SDK_COMPONENT_VOICE_AGENT -> "VoiceAgent"
            SDKComponent.SDK_COMPONENT_DIFFUSION -> "Diffusion"
            SDKComponent.SDK_COMPONENT_RAG -> "RAG"
            SDKComponent.SDK_COMPONENT_EMBEDDINGS -> "Embeddings"
            SDKComponent.SDK_COMPONENT_WAKEWORD -> "Wakeword"
            SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION -> "SpeakerDiarization"
            SDKComponent.SDK_COMPONENT_SEMANTIC_SEGMENTATION -> "SemanticSegmentation"
            SDKComponent.SDK_COMPONENT_UNSPECIFIED -> "UnknownComponent"
        }
