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
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVADProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collect
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory

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
    channelFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        // Ensure the native VAD component exists; the stream callback is
        // registered per-handle and C++ drives the event envelope (seq,
        // timestamp_us, request_id, kind) via dispatch_vad_stream_event.
        CppBridgeVADProto.create()
        val handle = CppBridgeVADProto.getHandle()

        val listener =
            NativeProtoProgressListener { bytes ->
                val event =
                    try {
                        VADStreamEvent.ADAPTER.decode(bytes)
                    } catch (t: Throwable) {
                        close(t)
                        return@NativeProtoProgressListener false
                    }
                event.statistics?.let { vadStatisticsCallback?.invoke(it) }
                    ?: event.result?.let {
                        vadStatisticsCallback?.invoke(VADStatistics(current_energy = it.energy))
                    }
                trySendBlocking(event)
                true
            }

        val registerRc = RunAnywhereBridge.racVadSetStreamProtoCallback(handle, listener)
        if (registerRc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation(
                "racVadSetStreamProtoCallback failed with rc=$registerRc",
            )
        }

        val sessionId =
            RunAnywhereBridge.racVadStreamStartProto(
                handle,
                VADOptions.ADAPTER.encode(options),
            )
        if (sessionId == 0L) {
            RunAnywhereBridge.racVadSetStreamProtoCallback(handle, null)
            throw SDKException.operation("racVadStreamStartProto returned 0")
        }

        try {
            audioSamples.collect { samples ->
                vadAudioBufferCallback?.invoke(samples)
                val pcmBytes = samples.toPcm16LeBytes()
                val feedRc =
                    RunAnywhereBridge.racVadStreamFeedAudioProto(sessionId, pcmBytes)
                if (feedRc != RunAnywhereBridge.RAC_SUCCESS) {
                    throw SDKException.operation(
                        "racVadStreamFeedAudioProto failed with rc=$feedRc",
                    )
                }
            }
            RunAnywhereBridge.racVadStreamStopProto(sessionId)
        } finally {
            // Ensure the session and listener are always torn down, whether
            // the upstream flow completes normally, errors, or is cancelled.
            RunAnywhereBridge.racVadStreamCancelProto(sessionId)
            RunAnywhereBridge.racVadSetStreamProtoCallback(handle, null)
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

/**
 * Convert normalized Float PCM samples in `[-1.0, 1.0]` to little-endian
 * int16 PCM bytes for `rac_vad_stream_feed_audio_proto`, which expects the
 * raw byte encoding used throughout the C ABI (`RAC_STT_BYTES_PER_SAMPLE`).
 */
private fun FloatArray.toPcm16LeBytes(): ByteArray {
    val bytes = ByteArray(size * 2)
    var byteIndex = 0
    for (sample in this) {
        val clamped = sample.coerceIn(-1f, 1f)
        val pcm = (clamped * Short.MAX_VALUE.toFloat()).toInt()
        bytes[byteIndex] = (pcm and 0xFF).toByte()
        bytes[byteIndex + 1] = ((pcm shr 8) and 0xFF).toByte()
        byteIndex += 2
    }
    return bytes
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — VAD lifecycle parity with Swift's RunAnywhere+VAD.swift
// Backed by CppBridgeVADProto (which owns the native handle + state).
// ─────────────────────────────────────────────────────────────────────────────

@Volatile private var vadAudioBufferCallback: ((FloatArray) -> Unit)? = null

@Volatile private var vadSpeechActivityCallback: ((VADStreamEventKind) -> Unit)? = null

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
    callback: (VADStreamEventKind) -> Unit,
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
        CppBridgeModelLifecycleProto
            .snapshot(SDKComponent.SDK_COMPONENT_VAD)
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
