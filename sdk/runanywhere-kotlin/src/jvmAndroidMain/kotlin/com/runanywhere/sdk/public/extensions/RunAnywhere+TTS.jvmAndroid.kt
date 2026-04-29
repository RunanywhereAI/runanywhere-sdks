/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Text-to-Speech operations.
 * Wave 2 KOTLIN: now uses proto-canonical TTSOptions / TTSOutput / TTSSpeakResult.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSSynthesisMetadata
import ai.runanywhere.proto.v1.TTSVoiceInfo
import com.runanywhere.sdk.features.tts.TtsAudioPlayback
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import okio.ByteString.Companion.toByteString

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

actual suspend fun RunAnywhere.loadTTSModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ttsLogger.debug("Loading TTS model: $modelId")
    val modelInfo =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKException.tts("TTS model '$modelId' not found in registry")
    val localPath =
        modelInfo.localPath
            ?: throw SDKException.tts("TTS model '$modelId' is not downloaded")
    val result = CppBridgeTTS.loadModel(localPath, modelId, modelInfo.name)
    if (result != 0) {
        throw SDKException.tts("Failed to load TTS model '$modelId' (error code: $result)")
    }
    ttsLogger.info("TTS model loaded: $modelId")
}

actual suspend fun RunAnywhere.unloadTTSModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeTTS.unload()
    ttsLogger.info("TTS model unloaded")
}

actual suspend fun RunAnywhere.loadTTSVoice(voiceId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ttsLogger.debug("Loading TTS voice: $voiceId")

    val modelInfo =
        CppBridgeModelRegistry.get(voiceId)
            ?: throw SDKException.tts("Voice '$voiceId' not found in registry")

    val localPath =
        modelInfo.localPath
            ?: throw SDKException.tts("Voice '$voiceId' is not downloaded")

    val result = CppBridgeTTS.loadModel(localPath, voiceId, modelInfo.name)
    if (result != 0) {
        ttsLogger.error("Failed to load TTS voice '$voiceId' (error code: $result)")
        throw SDKException.tts("Failed to load TTS voice '$voiceId' (error code: $result)")
    }
    ttsLogger.info("TTS voice loaded: $voiceId")
}

actual suspend fun RunAnywhere.unloadTTSVoice() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeTTS.unload()
}

actual val RunAnywhere.isTTSVoiceLoaded: Boolean
    get() = CppBridgeTTS.isLoaded

actual val RunAnywhere.currentTTSVoiceId: String?
    get() = CppBridgeTTS.getLoadedModelId()

actual val RunAnywhere.isTTSVoiceLoadedSync: Boolean
    get() = CppBridgeTTS.isLoaded

actual suspend fun RunAnywhere.availableTTSVoices(): List<TTSVoiceInfo> {
    return CppBridgeTTS.getAvailableVoices().map { voice ->
        TTSVoiceInfo(
            id = voice.voiceId,
            display_name = voice.name.ifBlank { voice.voiceId },
            language_code = voice.language,
        )
    }
}

actual suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions,
): TTSOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val voiceId = CppBridgeTTS.getLoadedModelId() ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId)")

    val effectiveLanguage = options.language_code.ifBlank { CppBridgeTTS.Language.ENGLISH }
    val config =
        CppBridgeTTS.SynthesisConfig(
            speed = if (options.speaking_rate > 0f) options.speaking_rate else 1f,
            pitch = if (options.pitch > 0f) options.pitch else 1f,
            volume = if (options.volume > 0f) options.volume else 1f,
            sampleRate = 22050,
            language = effectiveLanguage,
        )

    val result = CppBridgeTTS.synthesize(text, config)
    ttsLogger.info("Synthesis complete: ${result.durationMs}ms audio")

    val metadata =
        TTSSynthesisMetadata(
            voice_id = voiceId,
            language_code = effectiveLanguage,
            processing_time_ms = result.processingTimeMs,
            character_count = text.length,
            audio_duration_ms = result.durationMs,
        )

    return TTSOutput(
        audio_data = result.audioData.toByteString(),
        audio_format = if (options.audio_format == AudioFormat.AUDIO_FORMAT_UNSPECIFIED) AudioFormat.AUDIO_FORMAT_PCM else options.audio_format,
        sample_rate = config.sampleRate,
        duration_ms = result.durationMs,
        metadata = metadata,
    )
}

actual fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions,
): Flow<ByteArray> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        val effectiveLanguage = options.language_code.ifBlank { CppBridgeTTS.Language.ENGLISH }
        val config =
            CppBridgeTTS.SynthesisConfig(
                speed = if (options.speaking_rate > 0f) options.speaking_rate else 1f,
                pitch = if (options.pitch > 0f) options.pitch else 1f,
                volume = if (options.volume > 0f) options.volume else 1f,
                sampleRate = 22050,
                language = effectiveLanguage,
            )

        try {
            CppBridgeTTS.synthesizeStream(text, config) { audioData, isLast ->
                trySend(audioData)
                !isLast // continue if not last chunk
            }
        } finally {
            close()
        }
        awaitClose()
    }

actual suspend fun RunAnywhere.stopSynthesis() {
    CppBridgeTTS.cancel()
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions,
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
