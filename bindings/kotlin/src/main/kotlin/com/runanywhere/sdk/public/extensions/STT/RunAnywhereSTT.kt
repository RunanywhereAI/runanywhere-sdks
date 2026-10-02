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
import ai.runanywhere.proto.v1.STTServiceState
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

/**
 * Snapshot the lifecycle STT service state (readiness, current model,
 * supported language codes). Mirrors Swift `RunAnywhere.sttState()`.
 */
@Deprecated("Use RunAnywhere.stt.state().")
suspend fun RunAnywhere.sttState(): STTServiceState {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ensureServicesReady()
    return CppBridgeSTT.state()
}

@Deprecated("Use RunAnywhere.stt.transcribe(audio, options).")
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
    sttLogger.debug("Transcribing audio: ${audio.size} bytes")

    val result = CppBridgeSTT.transcribe(audio, options)
    sttLogger.info(
        "Transcription complete (${result.duration_ms}ms): " +
            "${result.text.take(50)}${if (result.text.length > 50) "..." else ""}",
    )
    return result
}

@Deprecated("Use RunAnywhere.stt.openStream(format, options).")
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
                try {
                    CppBridgeSTT.transcribeSessionStream(audio, options, current) { partial ->
                        trySend(partial).isSuccess
                    }
                    close()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    close(e)
                }
            }
        awaitClose {
            streamJob.cancel()
        }
    }
