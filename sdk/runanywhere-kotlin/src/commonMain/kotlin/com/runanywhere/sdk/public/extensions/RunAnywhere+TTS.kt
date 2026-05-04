/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Text-to-Speech operations.
 * Calls C++ directly via CppBridge.TTS for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+TTS.swift exactly.
 *
 * Round 2 KOTLIN: Added loadTTSModel/unloadTTSModel public surface,
 * changed synthesizeStream to return Flow<ByteArray>, changed
 * availableTTSVoices to return List<TTSVoiceInfo>.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSVoiceInfo
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// MARK: - Model Loading

/**
 * Load a TTS model.
 *
 * @param modelId The model identifier
 * @throws Error if loading fails
 */
expect suspend fun RunAnywhere.loadTTSModel(modelId: String)

/**
 * Unload the currently loaded TTS model.
 */
expect suspend fun RunAnywhere.unloadTTSModel()

// MARK: - Voice Loading

/**
 * Load a TTS voice.
 *
 * @param voiceId The voice identifier
 * @throws Error if loading fails
 */
expect suspend fun RunAnywhere.loadTTSVoice(voiceId: String)

/**
 * Unload the currently loaded TTS voice.
 */
expect suspend fun RunAnywhere.unloadTTSVoice()

/**
 * Check if a TTS voice is loaded.
 *
 * Sync property — reads cached state from the component layer without suspension.
 */
expect val RunAnywhere.isTTSVoiceLoaded: Boolean

/**
 * Get the currently loaded TTS voice ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded TTS voice,
 * or null if no voice is loaded.
 */
expect val RunAnywhere.currentTTSVoiceId: String?

/**
 * Check if a TTS voice is loaded (non-suspend version for quick checks).
 *
 * This accesses cached state and doesn't require suspension.
 * @deprecated Use isTTSVoiceLoaded directly.
 */
expect val RunAnywhere.isTTSVoiceLoadedSync: Boolean

/**
 * Get available TTS voices.
 *
 * @return List of [TTSVoiceInfo] proto objects describing each available voice
 */
expect suspend fun RunAnywhere.availableTTSVoices(): List<TTSVoiceInfo>

// MARK: - Synthesis

/**
 * Synthesize text to speech.
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @return TTS output with audio data
 */
expect suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions = TTSOptions(),
): TTSOutput

/**
 * Stream audio chunks for long text synthesis.
 *
 * Returns a [Flow] that emits raw audio [ByteArray] chunks as they are synthesized.
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @return Flow of audio chunks
 */
expect fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions = TTSOptions(),
): Flow<ByteArray>

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
    options: TTSOptions = TTSOptions(),
): TTSSpeakResult

/**
 * Whether speech is currently playing.
 *
 * Sync property — reads cached state from the playback layer without suspension.
 */
expect val RunAnywhere.isSpeaking: Boolean

/**
 * Stop current speech playback.
 */
expect suspend fun RunAnywhere.stopSpeaking()
