package com.runanywhere.sdk.features.speakerdiarization

import com.runanywhere.sdk.core.capabilities.ComponentState
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow

// All types (SpeakerDiarizationOutput, SpeakerSegment, SpeakerProfile, etc.) are imported from
// the same package (SpeakerDiarizationModels.kt) - no need for explicit imports

/**
 * Speaker Diarization Capability - Public API wrapper for Speaker Diarization operations
 *
 * Aligned with iOS SpeakerDiarizationCapability pattern:
 * - Service lifecycle management (initialize, cleanup)
 * - Core operations (processAudio, getAllSpeakers, updateSpeakerName, reset)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps SpeakerDiarizationComponent and provides the interface expected by
 * the public RunAnywhere+SpeakerDiarization.kt extension functions.
 *
 * Like VAD, SpeakerDiarization is ServiceBasedCapability (not ModelLoadable) -
 * it initializes a service rather than loading a specific model.
 */
class SpeakerDiarizationCapability internal constructor(
    private val getComponent: () -> SpeakerDiarizationComponent,
) {
    private val logger = SDKLogger("SpeakerDiarizationCapability")

    // ============================================================================
    // MARK: - State Properties (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Whether Speaker Diarization is ready for use
     */
    val isReady: Boolean
        get() = getComponent().state == ComponentState.READY

    // ============================================================================
    // MARK: - Service Lifecycle (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Initialize Speaker Diarization with default configuration
     *
     * @throws SDKError if initialization fails
     */
    suspend fun initialize() {
        initialize(SpeakerDiarizationConfiguration())
    }

    /**
     * Initialize Speaker Diarization with custom configuration
     *
     * @param config Speaker Diarization configuration
     * @throws SDKError if initialization fails
     */
    suspend fun initialize(
        @Suppress("UNUSED_PARAMETER") config: SpeakerDiarizationConfiguration,
    ) {
        logger.info("Initializing Speaker Diarization")

        try {
            val component = getComponent()
            component.initialize()

            logger.info("Speaker Diarization initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize Speaker Diarization", e)
            throw SDKError.InitializationFailed("Speaker Diarization initialization failed: ${e.message}")
        }
    }

    /**
     * Cleanup Speaker Diarization resources
     */
    suspend fun cleanup() {
        logger.info("Cleaning up Speaker Diarization")

        try {
            getComponent().cleanup()
            logger.info("Speaker Diarization cleaned up")
        } catch (e: Exception) {
            logger.error("Failed to cleanup Speaker Diarization", e)
            throw e
        }
    }

    // ============================================================================
    // MARK: - Core Operations (iOS pattern)
    // ============================================================================

    /**
     * Process audio and identify speaker
     *
     * @param samples Audio samples to analyze
     * @return Information about the detected speaker
     * @throws SDKError if not ready
     */
    suspend fun processAudio(samples: FloatArray): SpeakerInfo {
        ensureReady()

        val component = getComponent()
        val input =
            SpeakerDiarizationInput(
                audioBuffer = samples,
                sampleRate = 16000,
            )

        val output = component.processAudio(input)

        // Return the most recently detected speaker (convert from profile)
        return output.speakers.lastOrNull()?.let { profile ->
            SpeakerInfo(
                id = profile.id,
                name = profile.name,
                confidence = profile.averageConfidence,
                embedding = profile.embedding,
            )
        } ?: SpeakerInfo(
            id = "SILENCE",
            name = null,
            confidence = 0.0f,
            embedding = null,
        )
    }

    /**
     * Process audio stream for real-time speaker identification
     *
     * @param audioStream Flow of audio samples
     * @return Flow of speaker information
     */
    fun processAudioStream(audioStream: Flow<ByteArray>): Flow<SpeakerInfo> {
        ensureReady()

        val component = getComponent()
        return component.processAudioStream(audioStream)
    }

    /**
     * Perform full diarization on audio
     *
     * @param samples Audio samples
     * @param sampleRate Sample rate of audio
     * @return Full diarization output with segments and speakers
     */
    suspend fun diarize(
        samples: FloatArray,
        sampleRate: Int = 16000,
    ): SpeakerDiarizationOutput {
        ensureReady()

        val component = getComponent()
        val input =
            SpeakerDiarizationInput(
                audioBuffer = samples,
                sampleRate = sampleRate,
            )

        return component.processAudio(input)
    }

    /**
     * Get all identified speakers
     *
     * @return Array of all speakers detected so far
     * @throws SDKError if not ready
     */
    fun getAllSpeakers(): List<SpeakerInfo> {
        ensureReady()

        val component = getComponent()
        return component.getAllSpeakers()
    }

    /**
     * Get speaker profile by ID
     *
     * @param speakerId The speaker ID
     * @return Speaker profile or null if not found
     */
    suspend fun getSpeakerProfile(speakerId: String): SpeakerProfile? {
        ensureReady()

        val component = getComponent()
        return component.getSpeakerProfile(speakerId)
    }

    /**
     * Update speaker name
     *
     * @param speakerId The speaker ID to update
     * @param name The new name for the speaker
     * @throws SDKError if not ready
     */
    suspend fun updateSpeakerName(
        speakerId: String,
        name: String,
    ) {
        ensureReady()

        logger.info("Updating speaker name: $speakerId -> $name")
        val component = getComponent()
        component.updateSpeakerName(speakerId, name)
    }

    /**
     * Reset the diarization state
     * Clears all speaker profiles and resets tracking
     *
     * @throws SDKError if not ready
     */
    suspend fun reset() {
        ensureReady()

        logger.info("Resetting speaker diarization state")
        val component = getComponent()
        component.reset()
    }

    // ============================================================================
    // MARK: - Event Callbacks (iOS pattern)
    // ============================================================================

    /**
     * Set callback for speaker detection
     */
    fun onSpeakerDetected(callback: (SpeakerInfo) -> Unit) {
        getComponent().onSpeakerDetected(callback)
    }

    /**
     * Set callback for speaker change
     */
    fun onSpeakerChanged(callback: (previous: SpeakerInfo?, current: SpeakerInfo) -> Unit) {
        getComponent().onSpeakerChanged(callback)
    }

    /**
     * Set callback for segment completion
     */
    fun onSegmentCompleted(callback: (SpeakerSegment) -> Unit) {
        getComponent().onSegmentCompleted(callback)
    }

    /**
     * Set callback for processing completion
     */
    fun onProcessingCompleted(callback: (SpeakerDiarizationOutput) -> Unit) {
        getComponent().onProcessingCompleted(callback)
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureReady() {
        if (!isReady) {
            throw SDKError.ComponentNotReady("Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.")
        }
    }
}

// All Speaker Diarization types (SpeakerInfo, SpeakerProfile, SpeakerSegment,
// SpeakerDiarizationOutput, etc.) are defined in SpeakerDiarizationModels.kt
// to avoid duplicate type definitions
