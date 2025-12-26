package com.runanywhere.sdk.features.speakerdiarization

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.events.EventBus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Speaker Diarization Capability - Actor-based capability for speaker identification and tracking
 *
 * Aligned with iOS SpeakerDiarizationCapability pattern:
 * - Direct service management (no intermediate component layer)
 * - Service lifecycle management (initialize, cleanup)
 * - Core operations (processAudio, getAllSpeakers, updateSpeakerName, reset)
 * - Event tracking
 *
 * Like VAD, SpeakerDiarization is ServiceBasedCapability (not ModelLoadable) -
 * it initializes a service rather than loading a specific model.
 */
class SpeakerDiarizationCapability internal constructor() {
    private val logger = SDKLogger("SpeakerDiarizationCapability")

    // MARK: - State

    /** Currently active service */
    private var service: SpeakerDiarizationService? = null

    /** Whether diarization is configured */
    private var isConfigured = false

    /** Current configuration */
    private var currentConfiguration: SpeakerDiarizationConfiguration? = null

    /** Processing mutex for thread safety */
    private val processingMutex = Mutex()

    // Event callbacks
    private var onSpeakerDetectedCallback: ((SpeakerInfo) -> Unit)? = null
    private var onSpeakerChangedCallback: ((previous: SpeakerInfo?, current: SpeakerInfo) -> Unit)? = null
    private var onSegmentCompletedCallback: ((SpeakerSegment) -> Unit)? = null
    private var onProcessingCompletedCallback: ((SpeakerDiarizationOutput) -> Unit)? = null

    // ============================================================================
    // MARK: - State Properties (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Whether Speaker Diarization is ready for use
     */
    val isReady: Boolean
        get() = isConfigured && service?.isReady == true

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
    suspend fun initialize(config: SpeakerDiarizationConfiguration) =
        processingMutex.withLock {
            logger.info("Initializing Speaker Diarization")

            try {
                // Create service through ModuleRegistry or use default
                val diarizationService =
                    if (ModuleRegistry.hasSpeakerDiarization) {
                        logger.info("Creating Speaker Diarization service from registry")
                        ModuleRegistry.createSpeakerDiarization(config)
                    } else {
                        // Fall back to default implementation
                        logger.info("No provider found, using default Speaker Diarization service")
                        val database = InMemorySpeakerDatabase()
                        val audioProcessor = PlatformAudioProcessor()
                        DefaultSpeakerDiarizationService(config, database, audioProcessor)
                    }

                // Initialize the service
                diarizationService.initialize(config.modelId)

                this.service = diarizationService
                this.currentConfiguration = config
                this.isConfigured = true

                // Publish event
                publishEvent(SpeakerDiarizationEvent.ProcessingStarted)

                logger.info("Speaker Diarization initialized successfully")
            } catch (e: Exception) {
                logger.error("Failed to initialize Speaker Diarization", e)
                isConfigured = false
                service = null
                throw SDKError.InitializationFailed("Speaker Diarization initialization failed: ${e.message}")
            }
        }

    /**
     * Cleanup Speaker Diarization resources
     */
    suspend fun cleanup() =
        processingMutex.withLock {
            logger.info("Cleaning up Speaker Diarization")

            try {
                service?.cleanup()
            } catch (e: Exception) {
                logger.warn("Error during cleanup: ${e.message}")
            }

            service = null
            isConfigured = false
            currentConfiguration = null

            // Clear callbacks
            onSpeakerDetectedCallback = null
            onSpeakerChangedCallback = null
            onSegmentCompletedCallback = null
            onProcessingCompletedCallback = null

            logger.info("Speaker Diarization cleaned up")
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
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        logger.debug("Processing audio for speaker identification")
        val speaker = currentService.processAudio(samples)

        // Trigger callback
        if (speaker.id != "SILENCE") {
            onSpeakerDetectedCallback?.invoke(speaker)
            publishEvent(SpeakerDiarizationEvent.SpeakerDetected(speaker))
        }

        return speaker
    }

    /**
     * Process audio stream for real-time speaker identification
     *
     * @param audioStream Flow of audio samples as ByteArray
     * @return Flow of speaker information
     */
    fun processAudioStream(audioStream: Flow<ByteArray>): Flow<SpeakerInfo> =
        flow {
            val currentService =
                service ?: throw SDKError.ComponentNotReady(
                    "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
                )

            audioStream.collect { audioData ->
                try {
                    // Convert audio data to float array (assuming 16-bit PCM)
                    val samples = convertBytesToFloatArray(audioData)

                    // Process audio chunk
                    val speaker = currentService.processAudio(samples)

                    // Emit speaker detection events
                    if (speaker.id != "SILENCE") {
                        onSpeakerDetectedCallback?.invoke(speaker)
                        publishEvent(SpeakerDiarizationEvent.SpeakerDetected(speaker))
                    }

                    emit(speaker)
                } catch (e: Exception) {
                    val error = SpeakerDiarizationError.ProcessingFailed(e.message ?: "Stream processing error")
                    publishEvent(SpeakerDiarizationEvent.Error(error))
                    throw error
                }
            }
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
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        publishEvent(SpeakerDiarizationEvent.ProcessingStarted)

        val result =
            currentService.performDetailedDiarization(samples, sampleRate)
                ?: throw SpeakerDiarizationError.ProcessingFailed("Diarization returned no results")

        // Convert to SpeakerDiarizationOutput
        val speakerProfiles =
            result.speakers.map { speaker ->
                SpeakerProfile(
                    id = speaker.id,
                    embedding = speaker.embedding,
                    totalSpeakingTime =
                        result.segments
                            .filter { it.speakerId == speaker.id }
                            .sumOf { it.speechDuration },
                    segmentCount = result.segments.count { it.speakerId == speaker.id },
                    name = speaker.name,
                    averageConfidence = result.confidence,
                    lastUpdated = System.currentTimeMillis(),
                )
            }

        val metadata =
            DiarizationMetadata(
                processingTime = result.processingTime,
                audioLength = samples.size.toDouble() / sampleRate,
                speakerCount = result.speakers.size,
                method = "energy",
                averageConfidence = result.confidence,
                segmentCount = result.segments.size,
            )

        val output =
            SpeakerDiarizationOutput(
                segments = result.segments,
                speakers = speakerProfiles,
                labeledTranscription = null,
                metadata = metadata,
            )

        publishEvent(SpeakerDiarizationEvent.ProcessingCompleted)
        onProcessingCompletedCallback?.invoke(output)

        return output
    }

    /**
     * Get all identified speakers
     *
     * @return Array of all speakers detected so far
     * @throws SDKError if not ready
     */
    fun getAllSpeakers(): List<SpeakerInfo> {
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        return currentService.getAllSpeakers()
    }

    /**
     * Get speaker profile by ID
     *
     * @param speakerId The speaker ID
     * @return Speaker profile or null if not found
     */
    suspend fun getSpeakerProfile(speakerId: String): SpeakerProfile? {
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        return currentService.getSpeakerProfile(speakerId)
    }

    /**
     * Update speaker name
     *
     * @param speakerId The speaker ID to update
     * @param name The new name for the speaker
     * @throws SDKError if not ready
     */
    suspend fun updateSpeakerName(speakerId: String, name: String) {
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        logger.info("Updating speaker name: $speakerId -> $name")
        currentService.updateSpeakerName(speakerId, name)
    }

    /**
     * Reset the diarization state
     * Clears all speaker profiles and resets tracking
     *
     * @throws SDKError if not ready
     */
    suspend fun reset() {
        val currentService =
            service ?: throw SDKError.ComponentNotReady(
                "Speaker Diarization not initialized. Call initializeSpeakerDiarization() first.",
            )

        logger.info("Resetting speaker diarization state")
        currentService.reset()
    }

    // ============================================================================
    // MARK: - Event Callbacks (iOS pattern)
    // ============================================================================

    /**
     * Set callback for speaker detection
     */
    fun onSpeakerDetected(callback: (SpeakerInfo) -> Unit) {
        this.onSpeakerDetectedCallback = callback
    }

    /**
     * Set callback for speaker change
     */
    fun onSpeakerChanged(callback: (previous: SpeakerInfo?, current: SpeakerInfo) -> Unit) {
        this.onSpeakerChangedCallback = callback
    }

    /**
     * Set callback for segment completion
     */
    fun onSegmentCompleted(callback: (SpeakerSegment) -> Unit) {
        this.onSegmentCompletedCallback = callback
    }

    /**
     * Set callback for processing completion
     */
    fun onProcessingCompleted(callback: (SpeakerDiarizationOutput) -> Unit) {
        this.onProcessingCompletedCallback = callback
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    /**
     * Convert byte array to float array (assuming 16-bit PCM)
     */
    private fun convertBytesToFloatArray(audioData: ByteArray): FloatArray {
        val samples = FloatArray(audioData.size / 2)
        for (i in samples.indices) {
            val index = i * 2
            val sample =
                (audioData[index].toInt() and 0xFF) or
                    (audioData[index + 1].toInt() shl 8)
            samples[i] = sample.toShort() / 32768.0f
        }
        return samples
    }

    /**
     * Publish event to event bus
     */
    private fun publishEvent(event: SpeakerDiarizationEvent) {
        try {
            EventBus.publish(event)
        } catch (e: Exception) {
            // Ignore event publishing errors to avoid affecting main processing
        }
    }
}
