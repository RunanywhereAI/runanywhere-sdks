/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for standalone speaker-diarization operations.
 * Calls C++ directly via CppBridgeDiarization for all operations.
 *
 * Mirrors Swift RunAnywhere+Diarization.swift exactly (offline `diarize` +
 * streaming `diarizeStream`).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DiarizationRequest
import ai.runanywhere.proto.v1.DiarizationStreamEventKind
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDiarization
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RADiarizationOptions
import com.runanywhere.sdk.public.types.RADiarizationRequest
import com.runanywhere.sdk.public.types.RADiarizationResult
import com.runanywhere.sdk.public.types.RADiarizationStreamEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import okio.ByteString.Companion.toByteString

/**
 * Run standalone speaker diarization through the currently-loaded
 * speaker-diarization model. `audioData` must match `options.encoding`.
 *
 * Mirrors Swift's `RunAnywhere.diarize(audioData:options:)` convenience.
 */
suspend fun RunAnywhere.diarize(
    audioData: ByteArray,
    options: RADiarizationOptions = RADiarizationOptions(),
): RADiarizationResult =
    diarize(
        DiarizationRequest(
            audio_data = audioData.toByteString(),
            options = options,
        ),
    )

/**
 * Canonical request-based standalone speaker-diarization entry point.
 *
 * Mirrors Swift's `RunAnywhere.diarize(_ request:)`. The model must already
 * have been imported/registered and loaded under
 * [ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION]; this call never downloads
 * weights or creates a second model owner.
 */
suspend fun RunAnywhere.diarize(request: RADiarizationRequest): RADiarizationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK")
    }
    ensureServicesReady()
    if (!loadedModelSnapshot(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION).found) {
        throw SDKException.modelNotLoaded()
    }
    return CppBridgeDiarization.diarize(request)
}

/**
 * Feed a persistent stream of raw PCM chunks into the currently-loaded
 * speaker-diarization model. UPDATE and FINAL events contain complete session
 * snapshots; the FINAL (or ERROR) event terminates the stream.
 *
 * Mirrors Swift's `RunAnywhere.diarizeStream(audio:options:)`.
 */
fun RunAnywhere.diarizeStream(
    audio: Flow<ByteArray>,
    options: RADiarizationOptions = RADiarizationOptions(),
): Flow<RADiarizationStreamEvent> =
    callbackFlow {
        if (!isInitialized) {
            close(SDKException.notInitialized("SDK"))
            return@callbackFlow
        }
        ensureServicesReady()

        val snapshot = loadedModelSnapshot(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION)
        if (!snapshot.found) {
            close(SDKException.modelNotLoaded())
            return@callbackFlow
        }

        // Dispatch off the collector's context: session start creates the
        // provider (blocking JNI) and every audio chunk is fed through a
        // blocking JNI call. Mirrors the STT streaming facade.
        val streamJob =
            launch(Dispatchers.IO) {
                try {
                    CppBridgeDiarization.diarizeSessionStream(audio, options, snapshot) { event ->
                        val delivered = trySend(event).isSuccess
                        if (event.kind == DiarizationStreamEventKind.DIARIZATION_STREAM_EVENT_KIND_FINAL ||
                            event.kind == DiarizationStreamEventKind.DIARIZATION_STREAM_EVENT_KIND_ERROR
                        ) {
                            close()
                        }
                        delivered
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
