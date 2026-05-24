/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeVAD.kt
 *
 * VAD component bridge — manages C++ VAD component lifecycle and the
 * proto-canonical `rac_vad_*_proto` C ABI.
 *
 * All generic scaffolding (handle creation, isLoaded, loadModel, unload,
 * destroy) lives in [ComponentActor]; this object only adds the
 * VAD-specific surfaces (`configure`, `process`, `statistics`, `cancel`,
 * `reset`) on top.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VAD.swift` (W3-4).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADProcessRequest
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADServiceState
import ai.runanywhere.proto.v1.VADStatistics
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAVADOptions
import com.runanywhere.sdk.public.types.RAVADResult
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

private fun checkRc(rc: Int, operation: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$operation failed with rc=$rc")
    }
}

/**
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VAD.swift`. Wraps
 * `rac_vad_*_proto` C ABI. Handle lifecycle lives in [inner].
 */
object CppBridgeVAD {
    /** Generic scaffold (handle / isLoaded / loadModel / unload / destroy). */
    internal val actor = ComponentActor(ComponentVTable.vad)

    private val logger = SDKLogger("CppBridge.VAD")

    // MARK: - Handle Management

    /** Get or create the VAD component handle. */
    suspend fun getHandle(): Long = actor.getHandle()

    // MARK: - State

    /** Whether a model is loaded. */
    val isLoaded: Boolean
        get() = actor.isLoaded

    /**
     * Whether the VAD component is initialized (queries the component, not
     * the model slot). Mirrors Swift's `isInitialized` property which calls
     * `rac_vad_component_is_initialized`. Returns false if the handle has
     * not been created.
     */
    suspend fun isInitialized(): Boolean {
        val handle = actor.existingHandle()
        if (handle == 0L) return false
        return RunAnywhereBridge.racVadComponentIsInitialized(handle)
    }

    /** Currently-loaded model id, or null. */
    val currentModelId: String?
        get() = actor.currentAssetId

    // MARK: - Model Lifecycle

    /** Load a VAD model (e.g., Silero VAD via ONNX backend). */
    suspend fun loadModel(modelPath: String, modelId: String, modelName: String) {
        actor.loadModel(path = modelPath, id = modelId, name = modelName)
    }

    /** Unload the current VAD model (reverts to energy-based VAD). */
    suspend fun unload() {
        actor.unload()
    }

    /**
     * Unload the current VAD model via `rac_vad_component_unload` (reverts
     * to energy-based VAD). Mirrors Swift's `unloadModel()` which calls the
     * dedicated VAD unload ABI distinct from the generic component cleanup.
     * No-op if the handle has not been created.
     */
    suspend fun unloadModel() {
        val handle = actor.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racVadComponentUnload(handle)
        actor.markAssetLoaded(null)
        logger.info("VAD model unloaded")
    }

    /**
     * Cleanup VAD component (release all resources) via
     * `rac_vad_component_cleanup`. Mirrors Swift's `cleanup()`. No-op if
     * the handle has not been created.
     */
    suspend fun cleanup() {
        val handle = actor.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racVadComponentCleanup(handle)
        logger.info("VAD cleaned up")
    }

    // MARK: - Cleanup

    /** Destroy the component. */
    suspend fun destroy() {
        actor.destroy()
    }

    // MARK: - VAD-specific operations

    /**
     * Cancel the current detection. Native ABI is the source of truth; no
     * Kotlin-side `isCancelled` flag is maintained. No-op if the handle has
     * not been created.
     */
    suspend fun cancel() {
        val handle = actor.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racVadComponentCancel(handle)
    }

    /**
     * Reset the VAD state for a new audio stream. No-op if the handle has
     * not been created.
     *
     * NOTE: This is the handle-based `rac_vad_component_reset` reset. For
     * the lifecycle-owned reset returning [VADServiceState], use
     * [resetLifecycle].
     */
    suspend fun reset() {
        val handle = actor.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racVadComponentReset(handle)
    }

    /** Configure the VAD component with a [VADConfiguration] proto. */
    suspend fun configure(configuration: VADConfiguration) {
        val handle = actor.getHandle()
        val rc =
            RunAnywhereBridge.racVadComponentConfigureProto(
                handle,
                VADConfiguration.ADAPTER.encode(configuration),
            )
        checkRc(rc, "racVadComponentConfigureProto")
    }

    /**
     * Run a single VAD detection pass via the lifecycle-loaded model.
     * Mirrors Swift `CppBridge.VAD.processLifecycle(request:)`.
     */
    suspend fun processLifecycle(request: VADProcessRequest): RAVADResult =
        decodeOrThrow(
            VADResult.ADAPTER,
            RunAnywhereBridge.racVadProcessLifecycleProto(
                VADProcessRequest.ADAPTER.encode(request),
            ),
            "racVadProcessLifecycleProto",
        )

    /** Handle-based path; prefer [processLifecycle] after lifecycle model load. */
    suspend fun process(samples: FloatArray, options: RAVADOptions = RAVADOptions()): RAVADResult {
        val handle = actor.getHandle()
        return decodeOrThrow(
            VADResult.ADAPTER,
            RunAnywhereBridge.racVadComponentProcessProto(
                handle,
                samples,
                VADOptions.ADAPTER.encode(options),
            ),
            "racVadComponentProcessProto",
        )
    }

    /** Read the current VAD statistics snapshot. */
    suspend fun statistics(): VADStatistics {
        val handle = actor.getHandle()
        return decodeOrThrow(
            VADStatistics.ADAPTER,
            RunAnywhereBridge.racVadComponentGetStatisticsProto(handle),
            "racVadComponentGetStatisticsProto",
        )
    }

    /**
     * Register a per-handle voice-activity callback that fires whenever the
     * VAD component emits a [SpeechActivityEvent]. Mirrors Swift's
     * `CppBridge.VAD.setActivityCallbackProto(_:)` which wraps
     * `rac_vad_component_set_activity_proto_callback`.
     *
     * The supplied [callback] receives each decoded event; decode failures
     * are logged and dropped (matching Swift behaviour). Pass `null` to
     * clear the callback registration.
     *
     * @throws SDKException with category `component` when the C ABI returns
     *   a non-success status.
     */
    suspend fun setActivityCallbackProto(callback: ((SpeechActivityEvent) -> Unit)?) {
        val handle = actor.getHandle()
        val listener: NativeProtoProgressListener? =
            callback?.let { onEvent ->
                NativeProtoProgressListener { bytes ->
                    try {
                        onEvent(SpeechActivityEvent.ADAPTER.decode(bytes))
                    } catch (e: Exception) {
                        logger.warn("Failed to decode SpeechActivityEvent: ${e.message}")
                    }
                    true
                }
            }
        val rc = RunAnywhereBridge.racVadComponentSetActivityProtoCallback(handle, listener)
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation("VAD activity callback failed: rc=$rc")
        }
    }

    // MARK: - Service Lifecycle (lifecycle-owned VAD service)
    //
    // Mirrors Swift's `initialize`/`start`/`stop`/`reset` actor methods on
    // `CppBridge.VAD`, which forward to the `*Lifecycle` proto surface in
    // `CppBridge+ModalityProtoABI.swift` (`configureLifecycle`,
    // `startLifecycle`, `stopLifecycle`, `resetLifecycle`).
    //
    // Each routes through the commons VAD lifecycle to the currently-loaded
    // VAD service (no handle threaded) and returns the canonical
    // [VADServiceState] reflecting the post-call state.
    //
    // Lifecycle configure/start/stop/reset/process JNI thunks are wired in
    // librunanywhere_jni.so. Public VAD inference uses [processLifecycle].

    /**
     * Initialize VAD — binds to the commons lifecycle VAD service.
     * Returns the post-configure service state. Mirrors Swift's
     * `initialize(_:RAVADConfiguration)`.
     *
     * If the lifecycle JNI export is missing (commons-side work pending),
     * falls back to the handle-based `rac_vad_component_configure_proto`
     * path so callers don't crash with [UnsatisfiedLinkError].
     */
    suspend fun initialize(config: VADConfiguration = VADConfiguration()): VADServiceState {
        return try {
            val state =
                decodeOrThrow(
                    VADServiceState.ADAPTER,
                    RunAnywhereBridge.racVadConfigureLifecycleProto(
                        VADConfiguration.ADAPTER.encode(config),
                    ),
                    "racVadConfigureLifecycleProto",
                )
            logger.info("VAD initialized (lifecycle)")
            state
        } catch (e: UnsatisfiedLinkError) {
            logger.warn(
                "VAD lifecycle JNI not available; falling back to handle-based configure: ${e.message}",
            )
            configure(config)
            VADServiceState(is_ready = true)
        }
    }

    /**
     * Start VAD processing on the lifecycle-loaded service. Returns the
     * post-start service state. Mirrors Swift's `start()`.
     *
     * If the lifecycle JNI export is missing, returns a default
     * [VADServiceState] with `is_ready = true` rather than crashing.
     * Handle-based VAD has no separate start step — the component is
     * implicitly ready after [configure] / [loadModel].
     */
    suspend fun start(): VADServiceState =
        try {
            decodeOrThrow(
                VADServiceState.ADAPTER,
                RunAnywhereBridge.racVadStartLifecycleProto(),
                "racVadStartLifecycleProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            logger.warn(
                "VAD lifecycle JNI not available; start is a no-op on handle-based path: ${e.message}",
            )
            VADServiceState(is_ready = true)
        }

    /**
     * Stop VAD processing on the lifecycle-loaded service. Returns the
     * post-stop service state. Mirrors Swift's `stop()`.
     *
     * If the lifecycle JNI export is missing, falls back to a [cancel] on
     * the handle-based path and returns a default [VADServiceState] rather
     * than crashing.
     */
    suspend fun stop(): VADServiceState =
        try {
            decodeOrThrow(
                VADServiceState.ADAPTER,
                RunAnywhereBridge.racVadStopLifecycleProto(),
                "racVadStopLifecycleProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            logger.warn(
                "VAD lifecycle JNI not available; falling back to handle-based cancel: ${e.message}",
            )
            cancel()
            VADServiceState(is_ready = false)
        }

    /**
     * Reset VAD internal state on the lifecycle-loaded service (adaptive
     * thresholds, speech segments, timing). Returns the post-reset service
     * state. Mirrors Swift's `reset()` (which forwards to
     * `resetLifecycle()`).
     *
     * Distinct from [reset], which uses the handle-based
     * `rac_vad_component_reset` path.
     *
     * If the lifecycle JNI export is missing, falls back to the
     * handle-based [reset] so callers don't crash with
     * [UnsatisfiedLinkError].
     */
    suspend fun resetLifecycle(): VADServiceState {
        return try {
            val state =
                decodeOrThrow(
                    VADServiceState.ADAPTER,
                    RunAnywhereBridge.racVadResetLifecycleProto(),
                    "racVadResetLifecycleProto",
                )
            logger.info("VAD state reset (lifecycle)")
            state
        } catch (e: UnsatisfiedLinkError) {
            logger.warn(
                "VAD lifecycle JNI not available; falling back to handle-based reset: ${e.message}",
            )
            reset()
            VADServiceState(is_ready = true)
        }
    }
}
