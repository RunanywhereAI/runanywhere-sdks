/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Text-to-Speech operations.
 * Calls C++ directly via CppBridge.TTS for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+TTS.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.TTSSpeakResult
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput
import kotlinx.coroutines.flow.Flow

// MARK: - Synthesis

/**
 * Synthesize text to speech.
 *
 * @param text Text to synthesize
 * @param options Synthesis options (defaults to `TTSOptions()`)
 * @return TTS output with audio data
 */
expect suspend fun RunAnywhere.synthesize(
    text: String,
    options: RATTSOptions = RATTSOptions(),
): RATTSOutput

/**
 * Stream audio chunks for long text synthesis.
 *
 * Mirrors Swift's `synthesizeStream(_:options:)` — yields generated [TTSOutput]
 * chunks as they are synthesized.
 *
 * @param text Text to synthesize
 * @param voiceId Optional override voice ID
 * @return Flow of generated TTS output chunks
 */
expect fun RunAnywhere.synthesizeStream(
    text: String,
    voiceId: String? = null,
): Flow<RATTSOutput>

/**
 * Stop current TTS synthesis.
 */
expect suspend fun RunAnywhere.stopSynthesis()

// MARK: - Speak (Simple API)

/**
 * Speak text aloud - the simplest way to use TTS.
 *
 * The SDK handles audio synthesis and playback internally.
 * Just call this method and the text will be spoken through the device speakers.
 *
 * Example:
 * ```kotlin
 * // Simple usage
 * RunAnywhere.speak("Hello world")
 *
 * // With options
 * val result = RunAnywhere.speak("Hello", TTSOptions(rate = 1.2f))
 * println("Duration: ${result.duration}s")
 * ```
 *
 * @param text Text to speak
 * @param options Synthesis options (rate, pitch, voice, etc.)
 * @return Result containing metadata about the spoken audio
 * @throws Error if synthesis or playback fails
 */
expect suspend fun RunAnywhere.speak(
    text: String,
    options: RATTSOptions = RATTSOptions(),
): TTSSpeakResult

/**
 * Whether speech is currently playing.
 *
 * Sync property — reads cached state from the playback layer without suspension.
 */
expect val RunAnywhere.isSpeaking: Boolean

/**
 * Stop current speech playback. Mirrors Swift's `stopSpeaking()`.
 */
expect suspend fun RunAnywhere.stopSpeaking()
