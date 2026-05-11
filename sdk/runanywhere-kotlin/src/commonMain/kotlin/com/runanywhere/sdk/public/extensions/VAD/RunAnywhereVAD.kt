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

import ai.runanywhere.proto.v1.VADStatistics
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
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
 * Process audio samples and stream generated VAD event envelopes.
 *
 * @param audioSamples Flow of audio samples
 * @return Flow of generated VAD stream events
 */
fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADStreamEvent> =
    streamVAD(audioSamples, RAVADOptions())

/**
 * Process audio samples and stream generated VAD event envelopes using options.
 *
 * Native audio capture and session ownership remain app/platform-owned; this
 * stream consumes already-captured PCM frames and emits generated proto events.
 */
expect fun RunAnywhere.streamVAD(
    audioSamples: Flow<FloatArray>,
    options: RAVADOptions,
): Flow<VADStreamEvent>

/**
 * Calibrate VAD with ambient noise.
 *
 * @param ambientAudioData Audio data of ambient noise
 */
expect suspend fun RunAnywhere.calibrateVAD(ambientAudioData: ByteArray)

/**
 * Reset VAD state.
 */
expect suspend fun RunAnywhere.resetVAD()

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — VAD lifecycle parity with Swift's RunAnywhere+VAD.swift
//
// Mirrors:
//   `initializeVAD()` / `initializeVAD(_ config:)`
//   `isVADReady`     / `startVAD()` / `stopVAD()`
//   `setVADSpeechActivityCallback(...)` / `setVADAudioBufferCallback(...)`
//   `cleanupVAD()`   / `loadVADModel(_)`
// ─────────────────────────────────────────────────────────────────────────────

/**
 * True when the VAD subsystem is initialized and ready to process audio.
 *
 * Mirrors Swift's `RunAnywhere.isVADReady` getter.
 */
expect suspend fun RunAnywhere.isVADReady(): Boolean

/**
 * Start VAD processing. Mirrors Swift's `RunAnywhere.startVAD()`.
 */
expect suspend fun RunAnywhere.startVAD()

/**
 * Stop VAD processing. Mirrors Swift's `RunAnywhere.stopVAD()`.
 */
expect suspend fun RunAnywhere.stopVAD()

/**
 * Set the speech-activity callback that fires whenever the VAD detects
 * the start or end of speech.
 *
 * Mirrors Swift's `RunAnywhere.setVADSpeechActivityCallback(_:)`.
 *
 * Idiomatic Kotlin alternative: collect [streamVAD] for a Flow.
 */
expect suspend fun RunAnywhere.setVADSpeechActivityCallback(callback: (VADStreamEventKind) -> Unit)

/**
 * Set the audio-buffer callback that fires for each processed VAD frame.
 *
 * Mirrors Swift's `RunAnywhere.setVADAudioBufferCallback(_:)`.
 */
expect suspend fun RunAnywhere.setVADAudioBufferCallback(callback: (FloatArray) -> Unit)

/**
 * Cleanup VAD resources. Mirrors Swift's `RunAnywhere.cleanupVAD()`.
 */
expect suspend fun RunAnywhere.cleanupVAD()

/**
 * Load a VAD model. Mirrors Swift's
 * `RunAnywhere.loadVADModel(_ modelId:)`.
 */
expect suspend fun RunAnywhere.loadVADModel(modelId: String)

/**
 * The currently loaded VAD model ID, or `null` if no model is loaded.
 * Mirrors Swift's `RunAnywhere.currentVADModel` getter.
 */
expect suspend fun RunAnywhere.currentVADModelId(): String?

/**
 * Detect speech in raw audio samples.
 *
 * Returns `true` if speech is detected, `false` otherwise.
 * Canonical cross-SDK name per §6 spec. New callers should prefer
 * `detectVoiceActivity` for richer output (confidence, energy, etc.).
 */
expect suspend fun RunAnywhere.detectSpeech(audioData: ByteArray): Boolean

/**
 * Set a callback to receive VAD statistics after each processing call.
 *
 * The callback is invoked after `detectVoiceActivity` or `streamVAD` processes
 * a frame, delivering ambient level, recent average, and recent max energy.
 *
 * @param callback Invoked with [VADStatistics] for each processed frame.
 */
expect fun RunAnywhere.setVADStatisticsCallback(callback: (VADStatistics) -> Unit)
