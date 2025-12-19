package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.capabilities.stt.STTCapability
import com.runanywhere.sdk.capabilities.stt.STTOptions
import com.runanywhere.sdk.capabilities.stt.STTResult
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.flow.Flow

// ═══════════════════════════════════════════════════════════════════════════
// RunAnywhere STT Extensions
// Speech-to-Text operations aligned with iOS RunAnywhere+STT.swift
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Model Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Load an STT model by ID
 *
 * @param modelId The model identifier (e.g., "whisper-base", "whisper-small")
 * @throws SDKError if loading fails or no provider is available
 */
suspend fun RunAnywhere.loadSTTModel(modelId: String) {
    requireInitialized()
    ensureServicesReady()

    val capability = sttCapability
        ?: throw SDKError.ComponentNotInitialized("STT capability not available")

    capability.loadModel(modelId)
}

/**
 * Unload the currently loaded STT model
 */
suspend fun RunAnywhere.unloadSTTModel() {
    requireInitialized()

    val capability = sttCapability ?: return
    capability.unload()
}

/**
 * Check if an STT model is currently loaded
 */
val RunAnywhere.isSTTModelLoaded: Boolean
    get() = sttCapability?.isModelLoaded ?: false

/**
 * Get the currently loaded STT model ID
 */
val RunAnywhere.currentSTTModelId: String?
    get() = sttCapability?.currentModelId

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Transcription API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Simple transcription with default options
 *
 * @param audioData Raw audio data (WAV, PCM, etc.)
 * @return Transcribed text
 */
suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    requireInitialized()
    ensureServicesReady()

    val capability = sttCapability
        ?: throw SDKError.ComponentNotReady("STT capability not available. Call loadSTTModel() first.")

    val result = capability.transcribe(audioData)
    return result.text
}

/**
 * Transcription with custom options
 *
 * @param audioData Raw audio data
 * @param options Transcription options
 * @return STTResult with transcribed text and metadata
 */
suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions = STTOptions()
): STTResult {
    requireInitialized()
    ensureServicesReady()

    val capability = sttCapability
        ?: throw SDKError.ComponentNotReady("STT capability not available. Call loadSTTModel() first.")

    return capability.transcribe(audioData, options)
}

/**
 * Stream transcription for real-time audio processing
 *
 * @param audioStream Flow of audio data chunks
 * @param options Transcription options
 * @return Flow of transcription text
 */
fun RunAnywhere.transcribeStream(
    audioStream: Flow<ByteArray>,
    options: STTOptions = STTOptions()
): Flow<String> {
    requireInitialized()

    val capability = sttCapability
        ?: throw SDKError.ComponentNotReady("STT capability not available. Call loadSTTModel() first.")

    return capability.streamTranscribe(audioStream, options)
}
