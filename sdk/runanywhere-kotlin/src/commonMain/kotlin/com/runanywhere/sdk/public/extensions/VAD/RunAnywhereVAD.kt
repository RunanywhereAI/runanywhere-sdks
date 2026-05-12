/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Voice Activity Detection operations.
 * Calls C++ directly via CppBridge.VAD for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+VAD.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVADOptions
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.flow.Flow

// MARK: - VAD Operations

/**
 * Detect voice activity in audio data.
 *
 * @param audioData Audio data to analyze
 * @return VAD result with speech detection and confidence
 */
expect suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): RAVADResult

/** Canonical cross-SDK signature: detectVoiceActivity(audio, options) returns VADResult. */
expect suspend fun RunAnywhere.detectVoiceActivity(
    audioData: ByteArray,
    options: RAVADOptions,
): RAVADResult

/**
 * Process audio samples and stream per-frame VAD results.
 *
 * Mirrors Swift `RunAnywhere.streamVAD(audio:)` which emits one
 * `RAVADResult` per input chunk. Native audio capture and session ownership
 * remain app/platform-owned; this stream consumes already-captured PCM
 * frames.
 *
 * @param audioSamples Flow of audio samples
 * @return Flow of per-chunk [RAVADResult]
 */
fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<RAVADResult> =
    streamVAD(audioSamples, RAVADOptions())

/**
 * Process audio samples and stream per-frame VAD results using options.
 *
 * Mirrors Swift `RunAnywhere.streamVAD(audio:)` — one [RAVADResult] per
 * input chunk.
 */
expect fun RunAnywhere.streamVAD(
    audioSamples: Flow<FloatArray>,
    options: RAVADOptions,
): Flow<RAVADResult>

/**
 * Reset VAD state.
 */
expect suspend fun RunAnywhere.resetVAD()
