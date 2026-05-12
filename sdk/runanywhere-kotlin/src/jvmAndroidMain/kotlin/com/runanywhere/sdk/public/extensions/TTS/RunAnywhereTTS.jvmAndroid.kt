/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Text-to-Speech operations.
 * Wave 2 KOTLIN: now uses proto-canonical TTSOptions / TTSOutput / TTSSpeakResult.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSVoiceInfo
import com.runanywhere.sdk.features.TTS.Services.TtsAudioPlayback
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

/**
 * Internal helper: list available TTS voices from the C ABI.
 *
 * Per Swift parity, the public surface uses the model registry filtered by
 * `MODEL_CATEGORY_SPEECH_SYNTHESIS` to enumerate voices. This helper is
 * retained as INTERNAL for callers that still need the
 * `racTtsComponentListVoicesProto` enumeration.
 */
internal suspend fun RunAnywhere.availableTTSVoicesInternal(): List<TTSVoiceInfo> {
    return CppBridgeTTS.voices()
}

actual suspend fun RunAnywhere.synthesize(
    text: String,
    options: RATTSOptions,
): RATTSOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    // Lifecycle check: mirrors Swift's `synthesize(_:options:)` which queries
    // `RunAnywhere.currentModel(category: .speechSynthesis)` and throws when
    // no TTS voice is loaded. Querying the lifecycle (canonical source of
    // truth) is required because `CppBridgeTTS` owns its own handle that is
    // separate from the lifecycle's handle.
    val current = CppBridgeModelLifecycle.currentModel(
        CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
    )
    if (current?.found != true) {
        throw SDKException.notInitialized("TTS voice not loaded")
    }

    val voiceId = current.model_id.takeIf { it.isNotEmpty() } ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId)")

    val result = CppBridgeTTS.synthesize(text, options)
    ttsLogger.info("Synthesis complete: ${result.duration_ms}ms audio")
    return result
}

actual fun RunAnywhere.synthesizeStream(
    text: String,
    options: RATTSOptions,
): Flow<RATTSOutput> =
    callbackFlow {
        if (!isInitialized) {
            close()
            return@callbackFlow
        }

        // Mirror synthesize(): query ModelLifecycle (the canonical source of
        // truth) instead of CppBridgeTTS's own handle. Swift's
        // `synthesizeStream` finishes the stream silently when no voice is
        // loaded; we mirror that by closing the Flow without emitting.
        val current = CppBridgeModelLifecycle.currentModel(
            CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
        )
        if (current?.found != true) {
            close()
            return@callbackFlow
        }

        try {
            CppBridgeTTS.synthesizeStream(text, options) { output ->
                trySend(output)
                true
            }
        } finally {
            close()
        }
        awaitClose()
    }

actual suspend fun RunAnywhere.stopSynthesis() {
    CppBridgeTTS.stop()
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: RATTSOptions,
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    // Convert Float32 PCM to WAV format using C++ utility (Swift parity).
    // TTS backends output raw Float32 PCM; AudioPlaybackManager expects a
    // complete WAV file (with header) for MediaPlayer / javax.sound.
    val sampleRate =
        when {
            output.sample_rate > 0 -> output.sample_rate
            options.sample_rate > 0 -> options.sample_rate
            else -> 22_050
        }
    val wavData = convertPcmToWav(output.audio_data.toByteArray(), sampleRate)

    if (wavData.isNotEmpty()) {
        try {
            ttsAudioPlayback.play(wavData)
            ttsLogger.debug("Audio playback completed")
        } catch (e: Exception) {
            ttsLogger.error("Audio playback failed: ${e.message}", throwable = e)
            throw if (e is SDKException) e else SDKException.tts("Failed to play audio: ${e.message}")
        }
    }

    return TTSSpeakResult(
        audio_format = output.audio_format,
        sample_rate = output.sample_rate,
        duration_ms = output.duration_ms,
        audio_size_bytes = output.audio_data.size.toLong(),
        metadata = output.metadata,
        timestamp_ms = output.timestamp_ms,
    )
}

/**
 * Convert Float32 PCM to WAV using the C++ audio utility (Swift parity).
 *
 * Mirrors Swift's `convertPCMToWAV(pcmData:sampleRate:)` which calls
 * `rac_audio_float32_to_wav`. Returns an empty ByteArray for empty input
 * and throws on conversion failure.
 */
private fun convertPcmToWav(pcmData: ByteArray, sampleRate: Int): ByteArray {
    if (pcmData.isEmpty()) return ByteArray(0)
    return RunAnywhereBridge.racAudioFloat32ToWav(pcmData, sampleRate)
        ?: throw SDKException.tts("Failed to convert PCM to WAV")
}

actual val RunAnywhere.isSpeaking: Boolean
    get() = ttsAudioPlayback.isPlaying

actual suspend fun RunAnywhere.stopSpeaking() {
    ttsAudioPlayback.stop()
    stopSynthesis()
}
