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

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RASTTOutput
import kotlinx.coroutines.flow.Flow

/**
 * Proto-aliased partial-result envelope mirroring Swift's
 * `RASTTPartialResult`. Resolves to the canonical Wire-generated
 * `ai.runanywhere.proto.v1.STTPartialResult` so there is exactly one
 * source of truth (idl/proto files).
 */
public typealias RASTTPartialResult = ai.runanywhere.proto.v1.STTPartialResult

// MARK: - Transcription

/**
 * Transcribe audio data to text. Mirrors Swift's `transcribe(audio:options:)`.
 *
 * Performs a lifecycle check via `RunAnywhere.currentModel(category=SPEECH_RECOGNITION)`
 * before bridging — throws `SDKException.modelNotLoaded` if no STT model is loaded.
 * Also lazily completes Phase 2 (`ensureServicesReady`) before invoking the bridge.
 *
 * @param audio Raw audio data
 * @param options Transcription options (defaults to `RASTTOptions()`)
 * @return Transcription output with text and metadata
 */
expect suspend fun RunAnywhere.transcribe(
    audio: ByteArray,
    options: RASTTOptions = RASTTOptions(),
): RASTTOutput

// MARK: - Streaming Transcription

/**
 * Stream transcription results from a flow of audio chunks.
 *
 * Mirrors Swift's `transcribeStream(audio:options:)` which consumes an
 * `AsyncStream<Data>` of PCM audio chunks and yields `RASTTPartialResult`
 * envelopes. Each partial result carries an incremental transcript and an
 * `is_final` flag; the stream closes after the final event or on error.
 *
 * Performs a lifecycle check via `RunAnywhere.currentModel(category=SPEECH_RECOGNITION)`
 * before subscribing — finishes the flow immediately if no STT model is loaded
 * (matches Swift's `continuation.finish()` early-exit).
 *
 * @param audio Flow of audio chunk byte arrays
 * @param options Transcription options (defaults to `RASTTOptions()` when null)
 * @return Flow of partial transcription envelopes
 */
expect fun RunAnywhere.transcribeStream(
    audio: Flow<ByteArray>,
    options: RASTTOptions? = null,
): Flow<RASTTPartialResult>
