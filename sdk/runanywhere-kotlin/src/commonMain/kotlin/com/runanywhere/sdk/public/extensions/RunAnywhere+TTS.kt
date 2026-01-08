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

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.TTS.TTSOutput
import com.runanywhere.sdk.public.extensions.TTS.TTSSpeakResult

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
 */
expect suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean

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
 */
expect val RunAnywhere.isTTSVoiceLoadedSync: Boolean

/**
 * Get available TTS voices.
 */
expect suspend fun RunAnywhere.availableTTSVoices(): List<String>

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
 * Stream synthesis for long text.
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param onAudioChunk Callback for each audio chunk
 * @return TTS output with full audio data
 */
expect suspend fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions = TTSOptions(),
    onAudioChunk: (ByteArray) -> Unit,
): TTSOutput

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
 */
expect suspend fun RunAnywhere.isSpeaking(): Boolean

/**
 * Stop current speech playback.
 */
expect suspend fun RunAnywhere.stopSpeaking()
