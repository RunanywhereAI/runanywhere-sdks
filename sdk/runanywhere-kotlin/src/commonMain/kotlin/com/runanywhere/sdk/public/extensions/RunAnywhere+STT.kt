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
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.STTTranscriptionResult

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
 */
expect suspend fun RunAnywhere.isSTTModelLoaded(): Boolean

/**
 * Get the currently loaded STT model ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded STT model,
 * or null if no model is loaded.
 */
expect val RunAnywhere.currentSTTModelId: String?

/**
 * Check if an STT model is loaded (non-suspend version for quick checks).
 *
 * This accesses cached state and doesn't require suspension.
 */
expect val RunAnywhere.isSTTModelLoadedSync: Boolean

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

// MARK: - Streaming Transcription

/**
 * Transcribe audio with streaming callbacks.
 *
 * @param audioData Audio data to transcribe
 * @param options Transcription options
 * @param onPartialResult Callback for partial results
 * @return Final transcription output
 */
expect suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions = STTOptions(),
    onPartialResult: (STTTranscriptionResult) -> Unit,
): STTOutput

/**
 * Process audio samples for streaming transcription.
 *
 * @param samples Audio samples as float array
 */
expect suspend fun RunAnywhere.processStreamingAudio(samples: FloatArray)

/**
 * Stop streaming transcription.
 */
expect suspend fun RunAnywhere.stopStreamingTranscription()
