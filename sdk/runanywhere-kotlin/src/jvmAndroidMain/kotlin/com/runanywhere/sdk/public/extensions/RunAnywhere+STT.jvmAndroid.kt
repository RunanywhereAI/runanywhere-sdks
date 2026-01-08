/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.STTTranscriptionResult
import com.runanywhere.sdk.public.extensions.STT.TranscriptionMetadata

actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    val result = transcribeWithOptions(audioData, STTOptions())
    return result.text
}

actual suspend fun RunAnywhere.unloadSTTModel() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeSTT.unload()
}

actual suspend fun RunAnywhere.isSTTModelLoaded(): Boolean {
    return CppBridgeSTT.isLoaded
}

actual val RunAnywhere.currentSTTModelId: String?
    get() = CppBridgeSTT.getLoadedModelId()

actual val RunAnywhere.isSTTModelLoadedSync: Boolean
    get() = CppBridgeSTT.isLoaded

actual suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions,
): STTOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)

    // Convert to CppBridgeSTT config
    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = options.language ?: CppBridgeSTT.Language.AUTO,
            sampleRate = options.sampleRate,
        )

    val result = CppBridgeSTT.transcribe(audioData, config)

    val metadata =
        TranscriptionMetadata(
            modelId = CppBridgeSTT.getLoadedModelId() ?: "unknown",
            processingTime = result.processingTimeMs / 1000.0,
            audioLength = audioLengthSec,
        )

    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        wordTimestamps = null,
        detectedLanguage = result.language,
        alternatives = null,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
    onPartialResult: (STTTranscriptionResult) -> Unit,
): STTOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)

    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = options.language ?: CppBridgeSTT.Language.AUTO,
            sampleRate = options.sampleRate,
        )

    val result =
        CppBridgeSTT.transcribeStream(audioData, config) { partialText, isFinal ->
            onPartialResult(STTTranscriptionResult(transcript = partialText))
            true // Continue processing
        }

    val metadata =
        TranscriptionMetadata(
            modelId = CppBridgeSTT.getLoadedModelId() ?: "unknown",
            processingTime = result.processingTimeMs / 1000.0,
            audioLength = audioLengthSec,
        )

    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        wordTimestamps = null,
        detectedLanguage = result.language,
        alternatives = null,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.processStreamingAudio(samples: FloatArray) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val config = CppBridgeSTT.TranscriptionConfig()
    val audioData = samples.toByteArray()
    CppBridgeSTT.transcribe(audioData, config)
}

actual suspend fun RunAnywhere.stopStreamingTranscription() {
    CppBridgeSTT.cancel()
}

// Private helper
private fun estimateAudioLength(dataSize: Int): Double {
    val bytesPerSample = 2 // 16-bit
    val sampleRate = 16000.0
    val samples = dataSize.toDouble() / bytesPerSample.toDouble()
    return samples / sampleRate
}

private fun FloatArray.toByteArray(): ByteArray {
    val buffer = java.nio.ByteBuffer.allocate(size * 4)
    buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
    buffer.asFloatBuffer().put(this)
    return buffer.array()
}
