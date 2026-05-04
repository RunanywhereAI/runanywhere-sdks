/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Voice Activity Detection operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADEventType
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVADProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val vadLogger = SDKLogger.vad

actual suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    vadLogger.debug("Processing VAD frame: ${audioData.size} bytes")

    val result = CppBridgeVADProto.process(audioData.toFloatArray(), VADOptions())

    if (result.is_speech) {
        vadLogger.debug("Speech detected (confidence: ${String.format("%.2f", result.confidence)})")
    }

    return result
}

actual suspend fun RunAnywhere.getVADStatistics(): VADStatistics {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    return CppBridgeVADProto.statistics()
}

actual fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADResult> {
    return audioSamples.map { samples ->
        CppBridgeVADProto.process(samples, VADOptions())
    }
}

actual suspend fun RunAnywhere.calibrateVAD(ambientAudioData: ByteArray) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeVADProto.process(ambientAudioData.toFloatArray(), VADOptions())
}

actual suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeVAD.reset()
}

private fun ByteArray.toFloatArray(): FloatArray {
    val samples = FloatArray(size / 2)
    var byteIndex = 0
    for (i in samples.indices) {
        val lo = this[byteIndex].toInt() and 0xFF
        val hi = this[byteIndex + 1].toInt()
        val pcm = (hi shl 8) or lo
        samples[i] = (pcm.toShort().toFloat() / Short.MAX_VALUE.toFloat()).coerceIn(-1f, 1f)
        byteIndex += 2
    }
    return samples
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — VAD lifecycle parity with Swift's RunAnywhere+VAD.swift
// Backed by CppBridgeVAD (which owns the native handle + state).
// ─────────────────────────────────────────────────────────────────────────────

@Volatile private var vadAudioBufferCallback: ((FloatArray) -> Unit)? = null

@Volatile private var vadSpeechActivityCallback: ((VADEventType) -> Unit)? = null

actual suspend fun RunAnywhere.initializeVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Ensure native VAD component exists. CppBridgeVAD.create is idempotent.
    CppBridgeVAD.create()
}

actual suspend fun RunAnywhere.initializeVAD(configuration: VADConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeVAD.create()
    CppBridgeVADProto.configure(configuration)
}

actual suspend fun RunAnywhere.isVADReady(): Boolean {
    if (!isInitialized) return false
    return CppBridgeVAD.isReady
}

actual suspend fun RunAnywhere.startVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // No explicit start verb in CppBridgeVAD — readiness is "loaded model";
    // mirror Swift behaviour (start() forwards to C++ which is a no-op when
    // already ready).
    CppBridgeVAD.create()
}

actual suspend fun RunAnywhere.stopVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeVAD.cancel()
}

actual suspend fun RunAnywhere.setVADSpeechActivityCallback(
    callback: (VADEventType) -> Unit,
) {
    vadSpeechActivityCallback = callback
    // The Kotlin SDK's recommended path is `streamVAD(samples)`; this
    // setter records the callback for parity with Swift's API. The C
    // bridge wires its own activity-callback when a stream is collected.
}

actual suspend fun RunAnywhere.setVADAudioBufferCallback(callback: (FloatArray) -> Unit) {
    vadAudioBufferCallback = callback
}

actual suspend fun RunAnywhere.cleanupVAD() {
    if (!isInitialized) return
    unloadModel(ModelUnloadRequest(category = ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION))
    vadAudioBufferCallback = null
    vadSpeechActivityCallback = null
}

actual suspend fun RunAnywhere.loadVADModel(modelId: String) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val model = model(modelId) ?: throw SDKException.modelNotFound(modelId)
    val localPath = model.localPath ?: throw SDKException.modelNotLoaded(modelId)
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = model.framework.toProto(),
            ),
        )
    if (!result.success) {
        throw SDKException.modelLoadFailed(
            modelId,
            result.error_message.ifBlank { "Failed to load VAD model from $localPath" },
        )
    }
}

actual suspend fun RunAnywhere.unloadVADModel() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    unloadModel(ModelUnloadRequest(category = ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION))
}

actual val RunAnywhere.isVADModelLoaded: Boolean
    get() =
        CppBridgeModelLifecycleProto.snapshot(SDKComponent.SDK_COMPONENT_VAD)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            } ?: false

actual suspend fun RunAnywhere.currentVADModelId(): String? =
    currentModel(
        CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION),
    ).model_id.takeIf { it.isNotEmpty() }

actual suspend fun RunAnywhere.detectSpeech(audioData: ByteArray): Boolean {
    val result = detectVoiceActivity(audioData)
    vadStatisticsCallback?.invoke(
        VADStatistics(
            current_energy = result.energy,
            ambient_level = 0f,
            recent_avg = 0f,
            recent_max = 0f,
        ),
    )
    return result.is_speech
}

@Volatile private var vadStatisticsCallback: ((VADStatistics) -> Unit)? = null

actual fun RunAnywhere.setVADStatisticsCallback(callback: (VADStatistics) -> Unit) {
    vadStatisticsCallback = callback
}
