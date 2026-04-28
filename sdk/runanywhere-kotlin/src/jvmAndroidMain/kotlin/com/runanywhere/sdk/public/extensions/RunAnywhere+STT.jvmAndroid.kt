/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 * Wave 2 KOTLIN: now uses proto-canonical STTOptions / STTOutput / STTPartialResult.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTPartialResult
import ai.runanywhere.proto.v1.TranscriptionMetadata
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.foundation.protoext.bcp47
import com.runanywhere.sdk.public.RunAnywhere

private val sttLogger = SDKLogger.stt

actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    val result = transcribeWithOptions(audioData, STTOptions())
    return result.text
}

actual suspend fun RunAnywhere.unloadSTTModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
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
        throw SDKException.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)
    sttLogger.debug("Transcribing audio: ${audioData.size} bytes (${String.format("%.2f", audioLengthSec)}s)")

    // Convert proto STTOptions → bridge TranscriptionConfig
    val langCode =
        if (options.language == STTLanguage.STT_LANGUAGE_UNSPECIFIED) {
            CppBridgeSTT.Language.AUTO
        } else {
            options.language.bcp47
        }
    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = langCode,
            sampleRate = 16000,
        )

    val result = CppBridgeSTT.transcribe(audioData, config)
    sttLogger.info("Transcription complete: ${result.text.take(50)}${if (result.text.length > 50) "..." else ""}")

    val metadata =
        TranscriptionMetadata(
            model_id = CppBridgeSTT.getLoadedModelId() ?: "unknown",
            processing_time_ms = result.processingTimeMs,
            audio_length_ms = (audioLengthSec * 1000).toLong(),
        )

    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
    onPartialResult: (STTPartialResult) -> Unit,
): STTOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)

    val langCode =
        if (options.language == STTLanguage.STT_LANGUAGE_UNSPECIFIED) {
            CppBridgeSTT.Language.AUTO
        } else {
            options.language.bcp47
        }
    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = langCode,
            sampleRate = 16000,
        )

    val result =
        CppBridgeSTT.transcribeStream(audioData, config) { partialText, isFinal ->
            onPartialResult(STTPartialResult(text = partialText, is_final = isFinal))
            true // Continue processing
        }

    val metadata =
        TranscriptionMetadata(
            model_id = CppBridgeSTT.getLoadedModelId() ?: "unknown",
            processing_time_ms = result.processingTimeMs,
            audio_length_ms = (audioLengthSec * 1000).toLong(),
        )

    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.processStreamingAudio(samples: FloatArray) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
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
