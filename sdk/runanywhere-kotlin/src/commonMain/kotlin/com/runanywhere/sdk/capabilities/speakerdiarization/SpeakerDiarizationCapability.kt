package com.runanywhere.sdk.capabilities.speakerdiarization

import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationComponent
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationConfiguration
import com.runanywhere.sdk.components.speakerdiarization.SpeakerInfo
import com.runanywhere.sdk.components.speakerdiarization.SpeakerProfile
import com.runanywhere.sdk.components.speakerdiarization.SpeakerSegment
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationInput
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationOutput as ComponentOutput
import com.runanywhere.sdk.components.speakerdiarization.LabeledTranscription as ComponentLabeledTranscription
import com.runanywhere.sdk.components.speakerdiarization.DiarizationMetadata as ComponentMetadata
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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
    private val getComponent: () -> SpeakerDiarizationComponent
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
    suspend fun initialize(config: SpeakerDiarizationConfiguration) {
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
    suspend fun processAudio(samples: FloatArray): SpeakerDiarizationSpeakerInfo {
        ensureReady()

        val component = getComponent()
        val input = SpeakerDiarizationInput(
            audioBuffer = samples,
            sampleRate = 16000
        )

        val output = component.processAudio(input)

        // Return the most recently detected speaker (convert from profile)
        return output.speakers.lastOrNull()?.let { profile ->
            SpeakerDiarizationSpeakerInfo(
                id = profile.id,
                name = profile.name,
                confidence = profile.averageConfidence,
                embedding = profile.embedding
            )
        } ?: SpeakerDiarizationSpeakerInfo(
            id = "SILENCE",
            name = null,
            confidence = 0.0f,
            embedding = null
        )
    }

    /**
     * Process audio stream for real-time speaker identification
     *
     * @param audioStream Flow of audio samples
     * @return Flow of speaker information
     */
    fun processAudioStream(audioStream: Flow<ByteArray>): Flow<SpeakerDiarizationSpeakerInfo> {
        ensureReady()

        val component = getComponent()
        return component.processAudioStream(audioStream).map { speakerInfo ->
            speakerInfo.toPublicSpeakerInfo()
        }
    }

    /**
     * Perform full diarization on audio
     *
     * @param samples Audio samples
     * @param sampleRate Sample rate of audio
     * @return Full diarization output with segments and speakers
     */
    suspend fun diarize(samples: FloatArray, sampleRate: Int = 16000): SpeakerDiarizationOutput {
        ensureReady()

        val component = getComponent()
        val input = SpeakerDiarizationInput(
            audioBuffer = samples,
            sampleRate = sampleRate
        )

        val output = component.processAudio(input)
        return output.toPublicOutput()
    }

    /**
     * Get all identified speakers
     *
     * @return Array of all speakers detected so far
     * @throws SDKError if not ready
     */
    fun getAllSpeakers(): List<SpeakerDiarizationSpeakerInfo> {
        ensureReady()

        val component = getComponent()
        return component.getAllSpeakers().map { it.toPublicSpeakerInfo() }
    }

    /**
     * Get speaker profile by ID
     *
     * @param speakerId The speaker ID
     * @return Speaker profile or null if not found
     */
    suspend fun getSpeakerProfile(speakerId: String): SpeakerDiarizationProfile? {
        ensureReady()

        val component = getComponent()
        return component.getSpeakerProfile(speakerId)?.toPublicProfile()
    }

    /**
     * Update speaker name
     *
     * @param speakerId The speaker ID to update
     * @param name The new name for the speaker
     * @throws SDKError if not ready
     */
    suspend fun updateSpeakerName(speakerId: String, name: String) {
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
    fun onSpeakerDetected(callback: (SpeakerDiarizationSpeakerInfo) -> Unit) {
        getComponent().onSpeakerDetected { speakerInfo ->
            callback(speakerInfo.toPublicSpeakerInfo())
        }
    }

    /**
     * Set callback for speaker change
     */
    fun onSpeakerChanged(callback: (previous: SpeakerDiarizationSpeakerInfo?, current: SpeakerDiarizationSpeakerInfo) -> Unit) {
        getComponent().onSpeakerChanged { previous, current ->
            callback(
                previous?.toPublicSpeakerInfo(),
                current.toPublicSpeakerInfo()
            )
        }
    }

    /**
     * Set callback for segment completion
     */
    fun onSegmentCompleted(callback: (SpeakerDiarizationSegment) -> Unit) {
        getComponent().onSegmentCompleted { segment ->
            callback(segment.toPublicSegment())
        }
    }

    /**
     * Set callback for processing completion
     */
    fun onProcessingCompleted(callback: (SpeakerDiarizationOutput) -> Unit) {
        getComponent().onProcessingCompleted { output ->
            callback(output.toPublicOutput())
        }
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureReady() {
        if (!isReady) {
            throw SDKError.ComponentNotReady("Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.")
        }
    }

    private fun SpeakerInfo.toPublicSpeakerInfo(): SpeakerDiarizationSpeakerInfo {
        return SpeakerDiarizationSpeakerInfo(
            id = this.id,
            name = this.name,
            confidence = this.confidence,
            embedding = this.embedding
        )
    }

    private fun SpeakerProfile.toPublicProfile(): SpeakerDiarizationProfile {
        return SpeakerDiarizationProfile(
            id = this.id,
            embedding = this.embedding,
            totalSpeakingTime = this.totalSpeakingTime,
            segmentCount = this.segmentCount,
            name = this.name
        )
    }

    private fun SpeakerSegment.toPublicSegment(): SpeakerDiarizationSegment {
        return SpeakerDiarizationSegment(
            speakerId = this.speakerId,
            startTime = this.startTime,
            endTime = this.endTime,
            confidence = this.confidence
        )
    }

    private fun ComponentOutput.toPublicOutput(): SpeakerDiarizationOutput {
        return SpeakerDiarizationOutput(
            segments = this.segments.map { it.toPublicSegment() },
            speakers = this.speakers.map { it.toPublicProfile() },
            labeledTranscription = this.labeledTranscription?.toPublicLabeledTranscription(),
            metadata = this.metadata.toPublicMetadata(),
            timestamp = this.timestamp
        )
    }

    private fun ComponentLabeledTranscription.toPublicLabeledTranscription(): SpeakerDiarizationLabeledTranscription {
        return SpeakerDiarizationLabeledTranscription(
            segments = this.segments.map { seg ->
                SpeakerDiarizationLabeledSegment(
                    speakerId = seg.speakerId,
                    text = seg.text,
                    startTime = seg.startTime,
                    endTime = seg.endTime
                )
            },
            formattedTranscript = this.formattedTranscript
        )
    }

    private fun ComponentMetadata.toPublicMetadata(): SpeakerDiarizationMetadata {
        return SpeakerDiarizationMetadata(
            processingTime = this.processingTime,
            audioLength = this.audioLength,
            speakerCount = this.speakerCount,
            method = this.method
        )
    }
}

// ============================================================================
// MARK: - Public Types (Used by Capability layer)
// ============================================================================

/**
 * Speaker information returned by the capability
 * Aligned with iOS SpeakerDiarizationSpeakerInfo
 */
data class SpeakerDiarizationSpeakerInfo(
    /** Unique speaker identifier */
    val id: String,
    /** Optional speaker name (can be set by user) */
    val name: String?,
    /** Confidence score for speaker identification (0.0 - 1.0) */
    val confidence: Float?,
    /** Speaker embedding vector (for advanced matching) */
    val embedding: FloatArray?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerDiarizationSpeakerInfo) return false
        return id == other.id && name == other.name && confidence == other.confidence
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + (name?.hashCode() ?: 0)
        result = 31 * result + (confidence?.hashCode() ?: 0)
        return result
    }
}

/**
 * Speaker profile with statistics
 * Aligned with iOS SpeakerDiarizationProfile
 */
data class SpeakerDiarizationProfile(
    /** Unique speaker identifier */
    val id: String,
    /** Speaker embedding vector */
    val embedding: FloatArray?,
    /** Total speaking time in seconds */
    val totalSpeakingTime: Double,
    /** Number of speech segments */
    val segmentCount: Int,
    /** Optional speaker name */
    val name: String?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerDiarizationProfile) return false
        return id == other.id && name == other.name && segmentCount == other.segmentCount
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + (name?.hashCode() ?: 0)
        result = 31 * result + segmentCount
        return result
    }
}

/**
 * Time-stamped speaker segment
 * Aligned with iOS SpeakerDiarizationSegment
 */
data class SpeakerDiarizationSegment(
    /** Speaker ID for this segment */
    val speakerId: String,
    /** Start time in seconds */
    val startTime: Double,
    /** End time in seconds */
    val endTime: Double,
    /** Confidence score */
    val confidence: Float
) {
    /** Duration in seconds */
    val duration: Double
        get() = endTime - startTime
}

/**
 * Full diarization output
 * Aligned with iOS SpeakerDiarizationOutput
 */
data class SpeakerDiarizationOutput(
    /** Temporal segments with speaker assignments */
    val segments: List<SpeakerDiarizationSegment>,
    /** Speaker profiles with statistics */
    val speakers: List<SpeakerDiarizationProfile>,
    /** Labeled transcription (if STT output was provided) */
    val labeledTranscription: SpeakerDiarizationLabeledTranscription?,
    /** Processing metadata */
    val metadata: SpeakerDiarizationMetadata,
    /** Timestamp of processing */
    val timestamp: Long
)

/**
 * Labeled transcription with speaker attribution
 * Aligned with iOS SpeakerDiarizationLabeledTranscription
 */
data class SpeakerDiarizationLabeledTranscription(
    /** Labeled segments with speaker IDs and text */
    val segments: List<SpeakerDiarizationLabeledSegment>,
    /** Formatted transcript string */
    val formattedTranscript: String
)

/**
 * Labeled segment within a transcription
 */
data class SpeakerDiarizationLabeledSegment(
    /** Speaker ID */
    val speakerId: String,
    /** Transcribed text */
    val text: String,
    /** Start time in seconds */
    val startTime: Double,
    /** End time in seconds */
    val endTime: Double
)

/**
 * Processing metadata
 * Aligned with iOS SpeakerDiarizationMetadata
 */
data class SpeakerDiarizationMetadata(
    /** Processing time in seconds */
    val processingTime: Double,
    /** Audio length in seconds */
    val audioLength: Double,
    /** Number of speakers detected */
    val speakerCount: Int,
    /** Diarization method used */
    val method: String
)
