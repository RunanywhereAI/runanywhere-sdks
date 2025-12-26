package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.features.tts.TTSResult
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// ═══════════════════════════════════════════════════════════════════════════
// RunAnywhere TTS Extensions
// Text-to-Speech operations aligned with iOS RunAnywhere+TTS.swift
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Voice Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Load a TTS voice by ID
 *
 * @param voiceId The voice identifier
 * @throws SDKError if loading fails
 */
suspend fun RunAnywhere.loadTTSVoice(voiceId: String) {
    requireInitialized()
    ensureServicesReady()

    val capability =
        ttsCapability
            ?: throw SDKError.ComponentNotInitialized("TTS capability not available")

    capability.loadVoice(voiceId)
}

/**
 * Unload the currently loaded TTS voice
 */
suspend fun RunAnywhere.unloadTTSVoice() {
    requireInitialized()

    val capability = ttsCapability ?: return
    capability.unload()
}

/**
 * Check if a TTS voice is currently loaded
 */
val RunAnywhere.isTTSVoiceLoaded: Boolean
    get() = ttsCapability?.isVoiceLoaded ?: false

/**
 * Get the currently loaded TTS voice ID
 */
val RunAnywhere.currentTTSVoiceId: String?
    get() = ttsCapability?.currentVoiceId

/**
 * Get available TTS voices
 */
val RunAnywhere.availableTTSVoices: List<String>
    get() = ttsCapability?.availableVoices ?: emptyList()

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Synthesis API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Synthesize text to speech
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @return TTSResult with audio data
 */
suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions = TTSOptions(),
): TTSResult {
    requireInitialized()
    ensureServicesReady()

    val capability =
        ttsCapability
            ?: throw SDKError.ComponentNotReady("TTS capability not available. Call loadTTSVoice() first.")

    return capability.synthesize(text, options)
}

/**
 * Stream synthesis for long text
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @return Flow of audio data chunks
 */
fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions = TTSOptions(),
): Flow<ByteArray> {
    requireInitialized()

    val capability =
        ttsCapability
            ?: throw SDKError.ComponentNotReady("TTS capability not available. Call loadTTSVoice() first.")

    return capability.synthesizeStream(text, options)
}

/**
 * Stop current synthesis
 */
fun RunAnywhere.stopSynthesis() {
    ttsCapability?.stop()
}
