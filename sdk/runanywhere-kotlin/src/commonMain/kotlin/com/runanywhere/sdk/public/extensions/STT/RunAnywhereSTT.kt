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

import ai.runanywhere.proto.v1.STTStreamEvent
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RASTTOutput
import kotlinx.coroutines.flow.Flow

// MARK: - Transcription

/**
 * Transcribe audio data to text. Mirrors Swift's `transcribe(audio:options:)`.
 *
 * @param audio Raw audio data
 * @param options Transcription options (defaults to `STTOptions()`)
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
 * `AsyncStream<Data>` of PCM audio chunks and yields `STTStreamEvent`
 * envelopes (stream start, partial transcription chunks, final, error).
 *
 * @param audioData Flow of audio chunk byte arrays
 * @param options Transcription options (defaults to `STTOptions()` when null)
 * @return Flow of generated stream events
 */
expect fun RunAnywhere.transcribeStream(
    audioData: Flow<ByteArray>,
    options: RASTTOptions? = null,
): Flow<STTStreamEvent>
