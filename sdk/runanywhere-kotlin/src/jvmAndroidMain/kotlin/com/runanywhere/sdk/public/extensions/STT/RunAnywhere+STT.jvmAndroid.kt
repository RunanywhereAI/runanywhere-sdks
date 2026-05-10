/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 * Wave 2 KOTLIN: now uses proto-canonical STTOptions / STTOutput / STTStreamEvent.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTStreamEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTTProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory

private val sttLogger = SDKLogger.stt

private fun currentSttModelIdFromLifecycle(): String? =
    CppBridgeModelLifecycleProto
        .currentModel(
            CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
        )?.model_id
        ?.takeIf { it.isNotEmpty() }

actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    val result = transcribeWithOptions(audioData, STTOptions())
    return result.text
}

actual suspend fun RunAnywhere.unloadSTTModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeModelLifecycleProto.unload(
        ModelUnloadRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
    ) ?: throw SDKException.stt("Native model lifecycle unload proto API unavailable")
}

actual val RunAnywhere.isSTTModelLoaded: Boolean
    get() =
        CppBridgeModelLifecycleProto
            .snapshot(SDKComponent.SDK_COMPONENT_STT)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            }
            ?: false

actual val RunAnywhere.currentSTTModelId: String?
    get() = currentSttModelIdFromLifecycle()

actual suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions,
): STTOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)
    sttLogger.debug("Transcribing audio: ${audioData.size} bytes (${String.format("%.2f", audioLengthSec)}s)")

    val result = CppBridgeSTTProto.transcribe(audioData, options)
    sttLogger.info("Transcription complete: ${result.text.take(50)}${if (result.text.length > 50) "..." else ""}")
    return result
}

actual fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
): Flow<STTStreamEvent> =
    callbackFlow {
        if (!isInitialized) {
            close(SDKException.notInitialized("SDK not initialized"))
            return@callbackFlow
        }

        val streamJob =
            launch {
                try {
                    CppBridgeSTTProto.transcribeStream(audioData, options) { event ->
                        trySend(event).isSuccess
                    }
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
