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
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

private fun currentTtsVoiceIdFromLifecycle(): String? =
    CppBridgeModelLifecycle
        .currentModel(
            CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
        )?.model_id
        ?.takeIf { it.isNotEmpty() }

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

    val voiceId = currentTtsVoiceIdFromLifecycle() ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId)")

    val result = CppBridgeTTS.synthesize(text, options)
    ttsLogger.info("Synthesis complete: ${result.duration_ms}ms audio")
    return result
}

actual fun RunAnywhere.synthesizeStream(
    text: String,
    voiceId: String?,
): Flow<RATTSOutput> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        val options =
            voiceId?.takeIf { it.isNotBlank() }?.let { RATTSOptions(voice = it) }
                ?: RATTSOptions()

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
    // TTS generated-proto streaming is synchronous; cancellation is handled
    // by the native generation call and collector closure.
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: RATTSOptions,
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    if (output.audio_data.size > 0) {
        try {
            ttsAudioPlayback.play(output.audio_data.toByteArray())
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

actual val RunAnywhere.isSpeaking: Boolean
    get() = ttsAudioPlayback.isPlaying

actual suspend fun RunAnywhere.stopSpeaking() {
    ttsAudioPlayback.stop()
    stopSynthesis()
}
