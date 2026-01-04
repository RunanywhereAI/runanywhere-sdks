/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Text-to-Speech operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.TTS.TTSOutput
import com.runanywhere.sdk.public.extensions.TTS.TTSSpeakResult
import com.runanywhere.sdk.public.extensions.TTS.TTSSynthesisMetadata

actual suspend fun RunAnywhere.loadTTSVoice(voiceId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val modelInfo = CppBridgeModelRegistry.get(voiceId)
        ?: throw SDKError.tts("Voice '$voiceId' not found in registry")

    val localPath = modelInfo.localPath
        ?: throw SDKError.tts("Voice '$voiceId' is not downloaded")

    CppBridgeTTS.loadModel(localPath, voiceId)
}

actual suspend fun RunAnywhere.unloadTTSVoice() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeTTS.unload()
}

actual suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean {
    return CppBridgeTTS.isLoaded
}

actual val RunAnywhere.currentTTSVoiceId: String?
    get() = CppBridgeTTS.getLoadedModelId()

actual val RunAnywhere.isTTSVoiceLoadedSync: Boolean
    get() = CppBridgeTTS.isLoaded

actual suspend fun RunAnywhere.availableTTSVoices(): List<String> {
    // Get available voices from TTS component
    return CppBridgeTTS.getAvailableVoices().map { it.voiceId }
}

actual suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions
): TTSOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val voiceId = CppBridgeTTS.getLoadedModelId() ?: "unknown"

    val config = CppBridgeTTS.SynthesisConfig(
        speed = options.rate,
        pitch = options.pitch,
        volume = options.volume,
        sampleRate = options.sampleRate,
        language = options.language ?: CppBridgeTTS.Language.ENGLISH
    )

    val result = CppBridgeTTS.synthesize(text, config)

    val metadata = TTSSynthesisMetadata(
        voice = voiceId,
        language = config.language,
        processingTime = result.processingTimeMs / 1000.0,
        characterCount = text.length
    )

    return TTSOutput(
        audioData = result.audioData,
        format = options.audioFormat,
        duration = result.durationMs / 1000.0,
        phonemeTimestamps = null,
        metadata = metadata
    )
}

actual suspend fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions,
    onAudioChunk: (ByteArray) -> Unit
): TTSOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val voiceId = CppBridgeTTS.getLoadedModelId() ?: "unknown"

    val config = CppBridgeTTS.SynthesisConfig(
        speed = options.rate,
        pitch = options.pitch,
        volume = options.volume,
        sampleRate = options.sampleRate,
        language = options.language ?: CppBridgeTTS.Language.ENGLISH
    )

    val result = CppBridgeTTS.synthesizeStream(text, config) { audioData, isFinal ->
        onAudioChunk(audioData)
        true // Continue processing
    }

    val metadata = TTSSynthesisMetadata(
        voice = voiceId,
        language = config.language,
        processingTime = result.processingTimeMs / 1000.0,
        characterCount = text.length
    )

    return TTSOutput(
        audioData = result.audioData,
        format = options.audioFormat,
        duration = result.durationMs / 1000.0,
        phonemeTimestamps = null,
        metadata = metadata
    )
}

actual suspend fun RunAnywhere.stopSynthesis() {
    CppBridgeTTS.cancel()
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    // Platform-specific audio playback would happen here
    // TODO: Integrate with platform audio playback

    return TTSSpeakResult.from(output)
}

actual suspend fun RunAnywhere.isSpeaking(): Boolean {
    return false // TODO: Implement with platform audio playback
}

actual suspend fun RunAnywhere.stopSpeaking() {
    stopSynthesis()
}
