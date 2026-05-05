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

import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTStreamEvent
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// MARK: - Simple Transcription

/**
 * Simple voice transcription using default model.
 *
 * @param audioData Audio data to transcribe
 * @return Transcribed text
 */
expect suspend fun RunAnywhere.transcribe(audioData: ByteArray): String

// MARK: - Model Loading

/**
 * Unload the currently loaded STT model.
 */
expect suspend fun RunAnywhere.unloadSTTModel()

/**
 * Check if an STT model is loaded.
 *
 * Sync property — reads cached state from the component layer without suspension.
 */
expect val RunAnywhere.isSTTModelLoaded: Boolean

/**
 * Get the currently loaded STT model ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded STT model,
 * or null if no model is loaded.
 */
expect val RunAnywhere.currentSTTModelId: String?

// MARK: - Transcription with Options

/**
 * Transcribe audio data to text with options.
 *
 * @param audioData Raw audio data
 * @param options Transcription options
 * @return Transcription output with text and metadata
 */
expect suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions,
): STTOutput

/** Canonical cross-SDK signature: transcribe(audio, options) → STTOutput */
suspend fun RunAnywhere.transcribe(
    audio: ByteArray,
    options: STTOptions,
): STTOutput = transcribeWithOptions(audio, options)

// MARK: - Streaming Transcription

/**
 * Stream transcription results from audio data.
 *
 * Returns a [Flow] that emits generated [STTStreamEvent] envelopes for
 * stream start, partial transcription chunks, final chunks, and errors.
 *
 * @param audioData Audio data to transcribe
 * @param options Transcription options
 * @return Flow of generated stream events
 */
expect fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions = STTOptions(),
): Flow<STTStreamEvent>
