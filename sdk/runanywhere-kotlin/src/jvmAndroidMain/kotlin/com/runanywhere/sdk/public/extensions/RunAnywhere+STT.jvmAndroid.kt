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
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

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

actual val RunAnywhere.isSTTModelLoaded: Boolean
    get() = CppBridgeSTT.isLoaded

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

@Volatile private var sttStreamingActive: Boolean = false

actual val RunAnywhere.isStreamingSTT: Boolean
    get() = sttStreamingActive

actual fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
): Flow<STTPartialResult> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

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

        sttStreamingActive = true
        CppBridgeSTT.transcribeStream(audioData, config) { partialText, isFinal ->
            val result = STTPartialResult(text = partialText, is_final = isFinal)
            trySend(result)
            !isFinal // continue if not final
        }
        awaitClose { sttStreamingActive = false }
    }

actual suspend fun RunAnywhere.processStreamingAudio(samples: ByteArray) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val config = CppBridgeSTT.TranscriptionConfig()
    CppBridgeSTT.transcribe(samples, config)
}

actual suspend fun RunAnywhere.stopStreamingTranscription() {
    sttStreamingActive = false
    CppBridgeSTT.cancel()
}

// Private helper
private fun estimateAudioLength(dataSize: Int): Double {
    val bytesPerSample = 2 // 16-bit
    val sampleRate = 16000.0
    val samples = dataSize.toDouble() / bytesPerSample.toDouble()
    return samples / sampleRate
}
