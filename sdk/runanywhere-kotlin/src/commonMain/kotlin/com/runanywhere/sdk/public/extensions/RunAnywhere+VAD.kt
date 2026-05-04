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

import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADEventType
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// MARK: - VAD Operations

/**
 * Detect voice activity in audio data.
 *
 * @param audioData Audio data to analyze
 * @return VAD result with speech detection and confidence
 */
expect suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult

/** Canonical cross-SDK signature: detectVoiceActivity(audio, options) → VADResult */
@Suppress("UnusedParameter")
suspend fun RunAnywhere.detectVoiceActivity(
    audio: ByteArray,
    options: VADOptions,
): VADResult = detectVoiceActivity(audio)

/**
 * Get current VAD statistics for debugging.
 *
 * @return Current VAD statistics
 */
expect suspend fun RunAnywhere.getVADStatistics(): VADStatistics

/**
 * Process audio samples and stream VAD results.
 *
 * @param audioSamples Flow of audio samples
 * @return Flow of VAD results
 */
expect fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADResult>

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
 * Initialize VAD with default configuration.
 *
 * Mirrors Swift's `RunAnywhere.initializeVAD()`.
 */
expect suspend fun RunAnywhere.initializeVAD()

/**
 * Initialize VAD with the given configuration.
 *
 * Mirrors Swift's `RunAnywhere.initializeVAD(_ config:)`. This is the
 * Preferred overload when a configuration is available.
 */
expect suspend fun RunAnywhere.initializeVAD(configuration: VADConfiguration)

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
expect suspend fun RunAnywhere.setVADSpeechActivityCallback(callback: (VADEventType) -> Unit)

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
 * Unload the currently loaded VAD model.
 * Mirrors Swift's `RunAnywhere.unloadVADModel()`.
 */
expect suspend fun RunAnywhere.unloadVADModel()

/**
 * True if a VAD model is currently loaded.
 *
 * Sync property — reads cached state from the component layer without suspension.
 * Mirrors Swift's `RunAnywhere.isVADModelLoaded` getter.
 */
expect val RunAnywhere.isVADModelLoaded: Boolean

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
