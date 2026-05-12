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

import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
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

    // MARK: - Handle Management

    /** Get or create the VAD component handle. */
    suspend fun getHandle(): Long = actor.getHandle()

    // MARK: - State

    /** Whether a model is loaded. */
    val isLoaded: Boolean
        get() = actor.isLoaded

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

    /** Run a single VAD detection pass on the supplied audio samples. */
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
}
