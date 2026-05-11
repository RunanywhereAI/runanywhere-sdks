/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 * Wave 2 KOTLIN: now uses proto-canonical STTOptions / STTOutput / STTStreamEvent.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import ai.runanywhere.proto.v1.STTStreamEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RATranscriptionResult
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

private val sttLogger = SDKLogger.stt

private fun currentSttModelIdFromLifecycle(): String? =
    CppBridgeModelLifecycle
        .currentModel(
            CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
        )?.model_id
        ?.takeIf { it.isNotEmpty() }

actual val RunAnywhere.currentSTTModelId: String?
    get() = currentSttModelIdFromLifecycle()

actual suspend fun RunAnywhere.transcribe(
    audio: ByteArray,
    options: RASTTOptions,
): RATranscriptionResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audio.size)
    sttLogger.debug("Transcribing audio: ${audio.size} bytes (${String.format("%.2f", audioLengthSec)}s)")

    val result = CppBridgeSTT.transcribe(audio, options)
    sttLogger.info("Transcription complete: ${result.text.take(50)}${if (result.text.length > 50) "..." else ""}")
    return result
}

actual fun RunAnywhere.transcribeStream(
    audioData: Flow<ByteArray>,
    options: RASTTOptions?,
): Flow<STTStreamEvent> =
    callbackFlow {
        if (!isInitialized) {
            close(SDKException.notInitialized("SDK not initialized"))
            return@callbackFlow
        }

        val effectiveOptions = options ?: RASTTOptions()

        val streamJob =
            launch {
                try {
                    audioData.collect { chunk ->
                        CppBridgeSTT.transcribeStream(chunk, effectiveOptions) { event ->
                            trySend(event).isSuccess
                        }
                    }
                    // Mirror Swift's transcribeStream which emits a final
                    // sentinel event after the audio source completes.
                    trySend(STTStreamEvent())
                    close()
                } catch (e: Throwable) {
                    close(e)
                }
            }
        awaitClose {
            streamJob.cancel()
        }
    }

// Private helper
private fun estimateAudioLength(dataSize: Int): Double {
    val bytesPerSample = 2 // 16-bit
    val sampleRate = 16000.0
    val samples = dataSize.toDouble() / bytesPerSample.toDouble()
    return samples / sampleRate
}
