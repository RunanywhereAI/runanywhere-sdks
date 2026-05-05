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
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVADProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow

private val vadLogger = SDKLogger.vad

actual suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult =
    detectVoiceActivity(audioData, VADOptions())

actual suspend fun RunAnywhere.detectVoiceActivity(
    audioData: ByteArray,
    options: VADOptions,
): VADResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    vadLogger.debug("Processing VAD frame: ${audioData.size} bytes")

    val result = CppBridgeVADProto.process(audioData.toFloatArray(), options)

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

actual fun RunAnywhere.streamVAD(
    audioSamples: Flow<FloatArray>,
    options: VADOptions,
): Flow<VADStreamEvent> =
    flow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        var sequence = 0L
        fun nextSequence(): Long = ++sequence
        fun nowUs(): Long = System.currentTimeMillis() * 1000L
        val requestId = "vad-stream-${nowUs()}"

        emit(
            VADStreamEvent(
                seq = nextSequence(),
                timestamp_us = nowUs(),
                request_id = requestId,
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_STARTED,
            ),
        )

        try {
            audioSamples.collect { samples ->
                vadAudioBufferCallback?.invoke(samples)

                val result = CppBridgeVADProto.process(samples, options)
                val statistics =
                    result.statistics ?: if (options.include_statistics) {
                        CppBridgeVADProto.statistics()
                    } else {
                        null
                    }
                val callbackStatistics = statistics ?: VADStatistics(current_energy = result.energy)
                vadStatisticsCallback?.invoke(callbackStatistics)

                emit(
                    VADStreamEvent(
                        seq = nextSequence(),
                        timestamp_us = nowUs(),
                        request_id = requestId,
                        kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME,
                        result = result,
                        statistics = statistics,
                    ),
                )
            }

            emit(
                VADStreamEvent(
                    seq = nextSequence(),
                    timestamp_us = nowUs(),
                    request_id = requestId,
                    kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_STOPPED,
                ),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(
                VADStreamEvent(
                    seq = nextSequence(),
                    timestamp_us = nowUs(),
                    request_id = requestId,
                    kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_ERROR,
                    error_message = e.message ?: "VAD stream failed",
                ),
            )
            throw e
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
    CppBridgeVADProto.reset()
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
// Backed by CppBridgeVADProto (which owns the native handle + state).
// ─────────────────────────────────────────────────────────────────────────────

@Volatile private var vadAudioBufferCallback: ((FloatArray) -> Unit)? = null

@Volatile private var vadSpeechActivityCallback: ((VADEventType) -> Unit)? = null

actual suspend fun RunAnywhere.initializeVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Ensure native VAD component exists. CppBridgeVADProto.create is idempotent.
    CppBridgeVADProto.create()
}

actual suspend fun RunAnywhere.initializeVAD(configuration: VADConfiguration) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeVADProto.create()
    CppBridgeVADProto.configure(configuration)
}

actual suspend fun RunAnywhere.isVADReady(): Boolean {
    if (!isInitialized) return false
    return CppBridgeVADProto.isReady
}

actual suspend fun RunAnywhere.startVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // No explicit start verb in CppBridgeVADProto — readiness is "loaded model";
    // mirror Swift behaviour (start() forwards to C++ which is a no-op when
    // already ready).
    CppBridgeVADProto.create()
}

actual suspend fun RunAnywhere.stopVAD() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeVADProto.cancel()
}

actual suspend fun RunAnywhere.setVADSpeechActivityCallback(
    callback: (VADEventType) -> Unit,
) {
    vadSpeechActivityCallback = callback
    // Keep the Swift-parity setter until commons exposes a native
    // VADStreamEvent stream ABI; the current JNI activity callback emits only
    // SpeechActivityEvent bytes, not the public stream envelope.
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
    val localPath = model.local_path.takeIf { it.isNotEmpty() } ?: throw SDKException.modelNotLoaded(modelId)
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = model.framework,
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
