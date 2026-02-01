/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Text-to-Speech operations.
 * 
 * Uses TTSRouter to route between backends:
 * - KokoroTTSProvider: For Kokoro models (NPU-accelerated via QNN on Qualcomm devices)
 * - CppBridgeTTS: For other models (Sherpa-ONNX on CPU)
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.features.tts.TtsAudioPlayback
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.bridge.extensions.TTSRouter
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.TTS.TTSOutput
import com.runanywhere.sdk.public.extensions.TTS.TTSSpeakResult
import com.runanywhere.sdk.public.extensions.TTS.TTSSynthesisMetadata

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

actual suspend fun RunAnywhere.loadTTSVoice(voiceId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ttsLogger.debug("Loading TTS voice: $voiceId")

    val modelInfo =
        CppBridgeModelRegistry.get(voiceId)
            ?: throw SDKError.tts("Voice '$voiceId' not found in registry")

    val localPath =
        modelInfo.localPath
            ?: throw SDKError.tts("Voice '$voiceId' is not downloaded")

    // Use TTSRouter to route to appropriate backend (Kokoro or SherpaOnnx)
    TTSRouter.loadModel(localPath, voiceId, modelInfo.name).getOrElse { error ->
        ttsLogger.error("Failed to load TTS voice: ${error.message}")
        throw if (error is SDKError) error else SDKError.tts("Failed to load TTS voice: ${error.message}")
    }
    
    ttsLogger.info("TTS voice loaded: $voiceId (backend: ${TTSRouter.backendName})")
}

actual suspend fun RunAnywhere.unloadTTSVoice() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    TTSRouter.unload()
}

actual suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean {
    return TTSRouter.isLoaded
}

actual val RunAnywhere.currentTTSVoiceId: String?
    get() = TTSRouter.getLoadedModelId()

actual val RunAnywhere.isTTSVoiceLoadedSync: Boolean
    get() = TTSRouter.isLoaded

actual suspend fun RunAnywhere.availableTTSVoices(): List<String> {
    // Get available voices from TTS router (routes to appropriate backend)
    return TTSRouter.getAvailableVoices().map { it.voiceId }
}

actual suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions,
): TTSOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val voiceId = TTSRouter.getLoadedModelId() ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId, backend: ${TTSRouter.backendName})")

    val config =
        CppBridgeTTS.SynthesisConfig(
            speed = options.rate,
            pitch = options.pitch,
            volume = options.volume,
            sampleRate = options.sampleRate,
            language = options.language ?: CppBridgeTTS.Language.ENGLISH,
            voiceId = options.voice ?: "", // Pass voice for Kokoro
        )

    // Use TTSRouter which routes to appropriate backend
    val result = TTSRouter.synthesize(text, config).getOrElse { error ->
        ttsLogger.error("Synthesis failed: ${error.message}")
        throw if (error is SDKError) error else SDKError.tts("Synthesis failed: ${error.message}")
    }
    
    ttsLogger.info("Synthesis complete: ${result.durationMs}ms audio (backend: ${TTSRouter.backendName})")

    val metadata =
        TTSSynthesisMetadata(
            voice = voiceId,
            language = config.language,
            processingTime = result.processingTimeMs / 1000.0,
            characterCount = text.length,
        )

    return TTSOutput(
        audioData = result.audioData,
        format = options.audioFormat,
        duration = result.durationMs / 1000.0,
        phonemeTimestamps = null,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions,
    onAudioChunk: (ByteArray) -> Unit,
): TTSOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val voiceId = TTSRouter.getLoadedModelId() ?: "unknown"

    val config =
        CppBridgeTTS.SynthesisConfig(
            speed = options.rate,
            pitch = options.pitch,
            volume = options.volume,
            sampleRate = options.sampleRate,
            language = options.language ?: CppBridgeTTS.Language.ENGLISH,
            voiceId = options.voice ?: "", // Pass voice for Kokoro
        )

    // Use TTSRouter which routes to appropriate backend
    val result = TTSRouter.synthesizeStream(text, config) { audioData, isFinal ->
        onAudioChunk(audioData)
        true // Continue processing
    }.getOrElse { error ->
        ttsLogger.error("Streaming synthesis failed: ${error.message}")
        throw if (error is SDKError) error else SDKError.tts("Streaming synthesis failed: ${error.message}")
    }

    val metadata =
        TTSSynthesisMetadata(
            voice = voiceId,
            language = config.language,
            processingTime = result.processingTimeMs / 1000.0,
            characterCount = text.length,
        )

    return TTSOutput(
        audioData = result.audioData,
        format = options.audioFormat,
        duration = result.durationMs / 1000.0,
        phonemeTimestamps = null,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.stopSynthesis() {
    TTSRouter.cancel()
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions,
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    if (output.audioData.isNotEmpty()) {
        try {
            ttsAudioPlayback.play(output.audioData)
            ttsLogger.debug("Audio playback completed")
        } catch (e: Exception) {
            ttsLogger.error("Audio playback failed: ${e.message}", throwable = e)
            throw if (e is SDKError) e else SDKError.tts("Failed to play audio: ${e.message}")
        }
    }

    return TTSSpeakResult.from(output)
}

actual suspend fun RunAnywhere.isSpeaking(): Boolean {
    return ttsAudioPlayback.isPlaying
}

actual suspend fun RunAnywhere.stopSpeaking() {
    ttsAudioPlayback.stop()
    stopSynthesis()
}
