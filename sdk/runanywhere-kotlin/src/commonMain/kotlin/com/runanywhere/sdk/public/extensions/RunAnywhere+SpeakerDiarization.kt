package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationCapability
import com.runanywhere.sdk.features.speakerdiarization.SpeakerInfo
import com.runanywhere.sdk.features.speakerdiarization.SpeakerProfile
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationOutput
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationConfiguration
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.flow.Flow

/**
 * Speaker Diarization extension functions for RunAnywhere
 *
 * Provides public API for speaker diarization operations,
 * aligned with iOS RunAnywhere+SpeakerDiarization.swift pattern.
 */

// ============================================================================
// MARK: - Initialization
// ============================================================================

/**
 * Initialize speaker diarization with default configuration
 *
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.initializeSpeakerDiarization() {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    capability.initialize()
}

/**
 * Initialize speaker diarization with configuration
 *
 * @param config Speaker diarization configuration
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.initializeSpeakerDiarization(config: SpeakerDiarizationConfiguration) {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    capability.initialize(config)
}

/**
 * Check if speaker diarization is ready
 */
val RunAnywhere.isSpeakerDiarizationReady: Boolean
    get() = speakerDiarizationCapability?.isReady ?: false

// ============================================================================
// MARK: - Speaker Identification
// ============================================================================

/**
 * Process audio and identify speaker
 *
 * @param samples Audio samples to analyze
 * @return Information about the detected speaker
 * @throws SDKError if SDK is not initialized or speaker diarization not ready
 */
suspend fun RunAnywhere.identifySpeaker(samples: FloatArray): SpeakerInfo {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    return capability.processAudio(samples)
}

/**
 * Process audio stream for real-time speaker identification
 *
 * @param audioStream Flow of audio data
 * @return Flow of speaker information
 */
fun RunAnywhere.identifySpeakerStream(audioStream: Flow<ByteArray>): Flow<SpeakerInfo> {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    return capability.processAudioStream(audioStream)
}

/**
 * Perform full diarization on audio
 *
 * @param samples Audio samples
 * @param sampleRate Sample rate of audio (default: 16000)
 * @return Full diarization output with segments and speakers
 */
suspend fun RunAnywhere.diarize(samples: FloatArray, sampleRate: Int = 16000): SpeakerDiarizationOutput {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    return capability.diarize(samples, sampleRate)
}

/**
 * Get all identified speakers
 *
 * @return Array of all speakers detected so far
 * @throws SDKError if SDK is not initialized
 */
fun RunAnywhere.getAllSpeakers(): List<SpeakerInfo> {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    return capability.getAllSpeakers()
}

/**
 * Get speaker profile by ID
 *
 * @param speakerId The speaker ID
 * @return Speaker profile or null if not found
 */
suspend fun RunAnywhere.getSpeakerProfile(speakerId: String): SpeakerProfile? {
    requireInitialized()

    val capability = speakerDiarizationCapability ?: return null
    return capability.getSpeakerProfile(speakerId)
}

/**
 * Update speaker name
 *
 * @param speakerId The speaker ID to update
 * @param name The new name for the speaker
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.updateSpeakerName(speakerId: String, name: String) {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    capability.updateSpeakerName(speakerId, name)
}

/**
 * Reset speaker diarization state
 *
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.resetSpeakerDiarization() {
    requireInitialized()

    val capability = speakerDiarizationCapability
        ?: throw SDKError.ComponentNotInitialized("Speaker Diarization capability not available")

    capability.reset()
}

// ============================================================================
// MARK: - Event Callbacks
// ============================================================================

/**
 * Set callback for speaker detection events
 */
fun RunAnywhere.onSpeakerDetected(callback: (SpeakerInfo) -> Unit) {
    speakerDiarizationCapability?.onSpeakerDetected(callback)
}

/**
 * Set callback for speaker change events
 */
fun RunAnywhere.onSpeakerChanged(callback: (previous: SpeakerInfo?, current: SpeakerInfo) -> Unit) {
    speakerDiarizationCapability?.onSpeakerChanged(callback)
}

// ============================================================================
// MARK: - Cleanup
// ============================================================================

/**
 * Cleanup speaker diarization resources
 */
suspend fun RunAnywhere.cleanupSpeakerDiarization() {
    speakerDiarizationCapability?.cleanup()
}
