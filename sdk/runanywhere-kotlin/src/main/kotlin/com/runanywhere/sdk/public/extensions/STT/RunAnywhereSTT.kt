/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Speech-to-Text operations.
 * Calls C++ directly via CppBridge.STT for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+STT.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RASTTOutput
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

/**
 * Proto-aliased partial-result envelope mirroring Swift's
 * `RASTTPartialResult`. Resolves to the canonical Wire-generated
 * `ai.runanywhere.proto.v1.STTPartialResult` so there is exactly one
 * source of truth (idl/proto files).
 */
public typealias RASTTPartialResult = ai.runanywhere.proto.v1.STTPartialResult

// MARK: - Transcription

// MARK: - Streaming Transcription

private val sttLogger = SDKLogger.stt

suspend fun RunAnywhere.transcribe(
    audio: ByteArray,
    options: RASTTOptions = RASTTOptions.defaults(),
): RASTTOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ensureServicesReady()

    // Query ModelLifecycle instead of CppBridgeSTT's own handle — those
    // handles are separate, and the one loaded by `RunAnywhere.loadModel()`
    // is the lifecycle's, not the bridge actor's.
    val current =
        currentModel(
            CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
        )
    if (!current.found) {
        throw SDKException.modelNotLoaded()
    }

    val audioLengthSec = estimateAudioLength(audio.size)
    sttLogger.debug("Transcribing audio: ${audio.size} bytes (${String.format("%.2f", audioLengthSec)}s)")

    val result = CppBridgeSTT.transcribe(audio, options)
    sttLogger.info("Transcription complete: ${result.text.take(50)}${if (result.text.length > 50) "..." else ""}")
    return result
}

fun RunAnywhere.transcribeStream(
    audio: Flow<ByteArray>,
    options: RASTTOptions = RASTTOptions.defaults(),
): Flow<RASTTPartialResult> =
    callbackFlow {
        if (!isInitialized) {
            close()
            return@callbackFlow
        }
        ensureServicesReady()

        val current =
            currentModel(
                CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
            )
        if (!current.found) {
            // Mirror Swift's `continuation.finish()` early-exit when no STT
            // model is loaded.
            close()
            return@callbackFlow
        }

        // Dispatch off the collector's context: session start creates the
        // recognizer (seconds of blocking JNI) and every audio chunk is fed
        // through a blocking JNI call. Collected from the main thread (the
        // common case for view-models) this froze the UI and ANR'd the app.
        val streamJob =
            launch(Dispatchers.IO) {
                var sawFinal = false
                try {
                    CppBridgeSTT.transcribeSessionStream(audio, options, current) { partial ->
                        if (partial.is_final) {
                            sawFinal = true
                        }
                        trySend(partial).isSuccess
                    }
                    if (!sawFinal) {
                        trySend(RASTTPartialResult(is_final = true))
                    }
                    close()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    trySend(
                        RASTTPartialResult(
                            text = "STT stream failed: ${e.message ?: e::class.simpleName.orEmpty()}",
                            is_final = true,
                        ),
                    )
                    close()
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
