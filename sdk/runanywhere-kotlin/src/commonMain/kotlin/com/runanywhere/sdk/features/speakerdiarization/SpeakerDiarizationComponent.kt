package com.runanywhere.sdk.features.speakerdiarization

import com.runanywhere.sdk.core.capabilities.*
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Speaker Diarization Component
 * Matches iOS SpeakerDiarizationComponent architecture exactly
 */
class SpeakerDiarizationComponent(
    configuration: SpeakerDiarizationConfiguration,
    serviceContainer: ServiceContainer? = null,
) : BaseComponent<SpeakerDiarizationService>(configuration, serviceContainer) {
    // MARK: - Component Properties

    override val componentType: SDKComponent = SDKComponent.SPEAKER_DIARIZATION

    private val diarizationConfiguration: SpeakerDiarizationConfiguration
        get() = configuration as SpeakerDiarizationConfiguration

    private val processingMutex = Mutex()
    private var isProcessing = false

    // Event callbacks matching iOS implementation
    private var onSpeakerDetected: ((SpeakerInfo) -> Unit)? = null
    private var onSpeakerChanged: ((previous: SpeakerInfo?, current: SpeakerInfo) -> Unit)? = null
    private var onSegmentCompleted: ((SpeakerSegment) -> Unit)? = null
    private var onProcessingCompleted: ((SpeakerDiarizationOutput) -> Unit)? = null
    private var onError: ((SpeakerDiarizationError) -> Unit)? = null

    // MARK: - Service Creation

    override suspend fun createService(): SpeakerDiarizationService {
        // Create the default speaker diarization service directly
        // Simplified implementation without provider pattern
        val database = InMemorySpeakerDatabase()
        val audioProcessor = PlatformAudioProcessor()
        return DefaultSpeakerDiarizationService(diarizationConfiguration, database, audioProcessor)
    }

    override suspend fun initializeService() {
        service?.initialize(diarizationConfiguration.modelId)
            ?: throw SDKError.ServiceNotAvailable("Speaker Diarization service not available")
    }

    // MARK: - Processing Methods

    /**
     * Process audio for real-time speaker detection
     */
    suspend fun processAudio(input: SpeakerDiarizationInput): SpeakerDiarizationOutput {
        ensureReady()

        return processingMutex.withLock {
            if (isProcessing && !diarizationConfiguration.enableRealTimeProcessing) {
                throw SDKError.InvalidState("Component is already processing audio")
            }

            isProcessing = true
            val startTime = System.currentTimeMillis()

            try {
                val service =
                    this.service
                        ?: throw SDKError.ServiceNotAvailable("Speaker Diarization service not available")

                input.validate()
                state = ComponentState.PROCESSING

                // Emit processing started event
                publishEvent(SpeakerDiarizationEvent.ProcessingStarted)

                val result: SpeakerDiarizationOutput

                if (diarizationConfiguration.batchProcessingMode && input.audioBuffer != null) {
                    // Batch processing for complete audio
                    result = performBatchDiarization(input, service)
                } else {
                    // Real-time processing
                    result = performRealTimeDiarization(input, service)
                }

                // Emit processing completed event
                publishEvent(SpeakerDiarizationEvent.ProcessingCompleted)
                onProcessingCompleted?.invoke(result)

                state = ComponentState.READY
                return result
            } catch (e: Exception) {
                state = ComponentState.FAILED
                val error =
                    when (e) {
                        is SpeakerDiarizationError -> e
                        else -> SpeakerDiarizationError.ProcessingFailed(e.message ?: "Unknown processing error")
                    }
                publishEvent(SpeakerDiarizationEvent.Error(error))
                onError?.invoke(error)
                throw error
            } finally {
                isProcessing = false
            }
        }
    }

    /**
     * Stream audio processing for real-time diarization
     */
    fun processAudioStream(audioFlow: Flow<ByteArray>): Flow<SpeakerInfo> =
        flow {
            ensureReady()

            val service =
                this@SpeakerDiarizationComponent.service
                    ?: throw SDKError.ServiceNotAvailable("Speaker Diarization service not available")

            audioFlow.collect { audioData ->
                try {
                    // Convert audio data to float array (assuming 16-bit PCM)
                    val samples = convertBytesToFloatArray(audioData)

                    // Process audio chunk
                    val speaker = service.processAudio(samples)

                    // Emit speaker detection events
                    if (speaker.id != "SILENCE") {
                        onSpeakerDetected?.invoke(speaker)
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
     * Get all detected speakers
     */
    fun getAllSpeakers(): List<SpeakerInfo> {
        ensureReady()
        return service?.getAllSpeakers() ?: emptyList()
    }

    /**
     * Get speaker profile by ID
     */
    suspend fun getSpeakerProfile(speakerId: String): SpeakerProfile? {
        ensureReady()
        return service?.getSpeakerProfile(speakerId)
    }

    /**
     * Update speaker name/label
     */
    suspend fun updateSpeakerName(
        speakerId: String,
        name: String,
    ) {
        ensureReady()
        service?.updateSpeakerName(speakerId, name)
    }

    /**
     * Reset all speaker data
     */
    suspend fun reset() {
        service?.reset()
    }

    /**
     * Reset speaker profiles only
     */
    suspend fun resetProfiles() {
        service?.resetProfiles()
    }

    // MARK: - Event Handling

    /**
     * Set callback for speaker detection
     */
    fun onSpeakerDetected(callback: (SpeakerInfo) -> Unit) {
        this.onSpeakerDetected = callback
    }

    /**
     * Set callback for speaker change
     */
    fun onSpeakerChanged(callback: (previous: SpeakerInfo?, current: SpeakerInfo) -> Unit) {
        this.onSpeakerChanged = callback
    }

    /**
     * Set callback for segment completion
     */
    fun onSegmentCompleted(callback: (SpeakerSegment) -> Unit) {
        this.onSegmentCompleted = callback
    }

    /**
     * Set callback for processing completion
     */
    fun onProcessingCompleted(callback: (SpeakerDiarizationOutput) -> Unit) {
        this.onProcessingCompleted = callback
    }

    /**
     * Set callback for errors
     */
    fun onError(callback: (SpeakerDiarizationError) -> Unit) {
        this.onError = callback
    }

    // MARK: - Private Processing Methods

    /**
     * Perform batch diarization on complete audio
     */
    private suspend fun performBatchDiarization(
        input: SpeakerDiarizationInput,
        service: SpeakerDiarizationService,
    ): SpeakerDiarizationOutput {
        val audioBuffer =
            input.audioBuffer
                ?: throw SDKError.ValidationFailed("Audio buffer required for batch processing")

        val result =
            service.performDetailedDiarization(audioBuffer, input.sampleRate)
                ?: throw SpeakerDiarizationError.ProcessingFailed("Diarization returned no results")

        // Create speaker profiles from results
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
                    lastUpdated = getCurrentTimeMillis(),
                )
            }

        // Create labeled transcription if STT output provided
        val labeledTranscription =
            input.transcription?.let { sttOutput ->
                if (sttOutput.wordTimestamps != null) {
                    TranscriptionSpeakerIntegrator.createLabeledTranscription(
                        sttOutput.wordTimestamps,
                        result.segments,
                        speakerProfiles,
                    )
                } else {
                    TranscriptionSpeakerIntegrator.mapTranscriptionToSpeakers(
                        sttOutput.text,
                        result.segments,
                        speakerProfiles,
                    )
                }
            }

        // Create metadata
        val metadata =
            DiarizationMetadata(
                processingTime = result.processingTime,
                audioLength = audioBuffer.size.toDouble() / input.sampleRate,
                speakerCount = result.speakers.size,
                method = "energy",
                averageConfidence = result.confidence,
                segmentCount = result.segments.size,
            )

        return SpeakerDiarizationOutput(
            segments = result.segments,
            speakers = speakerProfiles,
            labeledTranscription = labeledTranscription,
            metadata = metadata,
        )
    }

    /**
     * Perform real-time diarization on audio chunk
     */
    private suspend fun performRealTimeDiarization(
        input: SpeakerDiarizationInput,
        service: SpeakerDiarizationService,
    ): SpeakerDiarizationOutput {
        val samples =
            if (input.audioBuffer != null) {
                input.audioBuffer
            } else {
                convertBytesToFloatArray(input.audioData)
            }

        // Process audio chunk
        val detectedSpeaker = service.processAudio(samples)

        // Create simple segment for real-time processing
        val segment =
            SpeakerSegment(
                speakerId = detectedSpeaker.id,
                startTime = 0.0,
                endTime = samples.size.toDouble() / input.sampleRate,
                confidence = detectedSpeaker.confidence ?: 0.8f,
            )

        // Get all speakers for profiles
        val allSpeakers = service.getAllSpeakers()
        val speakerProfiles =
            allSpeakers.map { speaker ->
                SpeakerProfile(
                    id = speaker.id,
                    embedding = speaker.embedding,
                    name = speaker.name,
                    lastUpdated = getCurrentTimeMillis(),
                )
            }

        // Create metadata for real-time processing
        val audioLength = samples.size.toDouble() / input.sampleRate
        val metadata =
            DiarizationMetadata(
                processingTime = 0.05, // Estimated for real-time
                audioLength = audioLength,
                speakerCount = allSpeakers.size,
                method = "energy",
                averageConfidence = detectedSpeaker.confidence ?: 0.8f,
                segmentCount = 1,
            )

        return SpeakerDiarizationOutput(
            segments = listOf(segment),
            speakers = speakerProfiles,
            labeledTranscription = null, // Real-time processing doesn't include transcription
            metadata = metadata,
        )
    }

    // MARK: - Utility Methods

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

    // MARK: - Cleanup

    override suspend fun performCleanup() {
        super.performCleanup()

        // Clear callbacks
        onSpeakerDetected = null
        onSpeakerChanged = null
        onSegmentCompleted = null
        onProcessingCompleted = null
        onError = null

        // Reset processing state
        isProcessing = false
    }
}
