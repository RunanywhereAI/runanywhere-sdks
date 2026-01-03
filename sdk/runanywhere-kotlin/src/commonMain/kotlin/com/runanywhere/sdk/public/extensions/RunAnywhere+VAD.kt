/*
 * Copyright 2024 RunAnywhere SDK
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
import com.runanywhere.sdk.public.extensions.VAD.VADConfiguration
import com.runanywhere.sdk.public.extensions.VAD.VADResult
import com.runanywhere.sdk.public.extensions.VAD.VADStatistics
import kotlinx.coroutines.flow.Flow

// MARK: - VAD Operations

/**
 * Detect voice activity in audio data.
 *
 * @param audioData Audio data to analyze
 * @return VAD result with speech detection and confidence
 */
expect suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult

/**
 * Configure VAD settings.
 *
 * @param configuration VAD configuration
 */
expect suspend fun RunAnywhere.configureVAD(configuration: VADConfiguration)

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
