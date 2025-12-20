package com.runanywhere.sdk.features.speakerdiarization

import com.runanywhere.sdk.features.stt.WordTimestamp
import kotlinx.coroutines.flow.Flow

// MARK: - Speaker Diarization Service Protocol

/**
 * Protocol for speaker diarization services (matches iOS SpeakerDiarizationService exactly)
 */
interface SpeakerDiarizationService {
    /**
     * Initialize the service with optional model path
     */
    suspend fun initialize(modelPath: String? = null)

    /**
     * Process audio samples for real-time speaker detection
     * Returns the current active speaker
     */
    fun processAudio(samples: FloatArray): SpeakerInfo

    /**
     * Perform detailed diarization on complete audio buffer
     * Returns comprehensive diarization result
     */
    suspend fun performDetailedDiarization(audioBuffer: FloatArray, sampleRate: Int = 16000): SpeakerDiarizationResult?

    /**
     * Get all detected speakers
     */
    fun getAllSpeakers(): List<SpeakerInfo>

    /**
     * Get speaker profile by ID
     */
    fun getSpeakerProfile(id: String): SpeakerProfile?

    /**
     * Update speaker name/label
     */
    fun updateSpeakerName(speakerId: String, name: String)

    /**
     * Reset all speaker profiles and history
     */
    fun reset()

    /**
     * Reset only speaker profiles (keep configuration)
     */
    fun resetProfiles()

    /**
     * Check if service is ready
     */
    val isReady: Boolean

    /**
     * Current processing configuration
     */
    val configuration: SpeakerDiarizationConfiguration?

    /**
     * Current model identifier
     */
    val currentModel: String?

    /**
     * Cleanup resources
     */
    suspend fun cleanup()
}

// MARK: - Audio Processor Interface

/**
 * Platform-specific audio processing interface (expect/actual pattern)
 */
expect class PlatformAudioProcessor() {
    /**
     * Create speaker embedding from audio samples
     * Uses platform-optimized algorithms (SIMD, DSP frameworks)
     */
    fun createEmbedding(audioSamples: FloatArray): FloatArray

    /**
     * Calculate cosine similarity between two embeddings
     * Uses platform-optimized vector operations
     */
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float

    /**
     * Calculate RMS energy of audio samples
     */
    fun calculateRMSEnergy(samples: FloatArray): Float

    /**
     * Extract audio features for speaker identification
     */
    fun extractFeatures(samples: FloatArray, sampleRate: Int): AudioFeatures

    /**
     * Apply windowing function to audio samples
     */
    fun applyWindow(samples: FloatArray, windowType: WindowType = WindowType.HANN): FloatArray

    /**
     * Segment audio into overlapping chunks
     */
    fun segmentAudio(
        samples: FloatArray,
        sampleRate: Int,
        windowSize: Double,
        stepSize: Double
    ): List<AudioChunk>
}

/**
 * Window functions for audio processing
 */
enum class WindowType {
    RECTANGULAR,
    HANN,
    HAMMING,
    BLACKMAN
}

// MARK: - Speaker Database Interface

/**
 * Interface for persistent speaker storage
 */
interface SpeakerDatabase {
    /**
     * Store speaker profile
     */
    suspend fun storeSpeaker(profile: SpeakerProfile)

    /**
     * Retrieve speaker profile by ID
     */
    suspend fun getSpeaker(id: String): SpeakerProfile?

    /**
     * Get all stored speakers
     */
    suspend fun getAllSpeakers(): List<SpeakerProfile>

    /**
     * Update speaker profile
     */
    suspend fun updateSpeaker(profile: SpeakerProfile)

    /**
     * Delete speaker profile
     */
    suspend fun deleteSpeaker(id: String)

    /**
     * Clear all speakers
     */
    suspend fun clearAllSpeakers()

    /**
     * Find speakers similar to embedding
     */
    suspend fun findSimilarSpeakers(embedding: FloatArray, threshold: Float): List<Pair<SpeakerProfile, Float>>
}

// MARK: - Speaker Manager

/**
 * Speaker management with clustering and identification
 */
class SpeakerManager(
    private val database: SpeakerDatabase,
    private val audioProcessor: PlatformAudioProcessor,
    private val configuration: SpeakerDiarizationConfiguration
) {
    private val activeSpeakers = mutableMapOf<String, SpeakerInfo>()
    private var speakerCounter = 0

    /**
     * Process audio chunk and return active speaker
     */
    suspend fun processAudioChunk(
        samples: FloatArray,
        startTime: Double,
        endTime: Double
    ): SpeakerInfo {
        // Extract features from audio
        val features = audioProcessor.extractFeatures(samples, configuration.sampleRate)

        // Check energy threshold
        if (features.rmsEnergy < configuration.energyThreshold) {
            // Return silence/no speaker
            return createSilenceSpeaker()
        }

        // Find matching speaker or create new one
        val matchingSpeaker = findMatchingSpeaker(features.embedding)

        return if (matchingSpeaker != null) {
            // Update existing speaker
            updateSpeakerActivity(matchingSpeaker, features, startTime, endTime)
            matchingSpeaker
        } else {
            // Create new speaker
            createNewSpeaker(features.embedding, startTime, endTime)
        }
    }

    /**
     * Find matching speaker based on embedding similarity
     */
    private suspend fun findMatchingSpeaker(embedding: FloatArray): SpeakerInfo? {
        var bestMatch: Pair<SpeakerInfo, Float>? = null

        // Check active speakers first
        for (speaker in activeSpeakers.values) {
            speaker.embedding?.let { speakerEmbedding ->
                val similarity = audioProcessor.cosineSimilarity(embedding, speakerEmbedding)
                if (similarity > configuration.speakerChangeThreshold) {
                    if (bestMatch == null || similarity > bestMatch!!.second) {
                        bestMatch = speaker to similarity
                    }
                }
            }
        }

        // Check database speakers if no active match
        if (bestMatch == null) {
            val similarSpeakers = database.findSimilarSpeakers(embedding, configuration.speakerChangeThreshold)
            if (similarSpeakers.isNotEmpty()) {
                val (profile, similarity) = similarSpeakers.first()
                val speakerInfo = SpeakerInfo(
                    id = profile.id,
                    name = profile.name,
                    confidence = similarity,
                    embedding = profile.embedding
                )
                activeSpeakers[profile.id] = speakerInfo
                return speakerInfo
            }
        }

        return bestMatch?.first
    }

    /**
     * Create new speaker
     */
    private suspend fun createNewSpeaker(
        embedding: FloatArray,
        startTime: Double,
        endTime: Double
    ): SpeakerInfo {
        val speakerId = "Speaker_${++speakerCounter}"
        val speaker = SpeakerInfo(
            id = speakerId,
            name = null, // Will be assigned later
            confidence = 0.8f, // Default confidence for new speakers
            embedding = embedding
        )

        // Add to active speakers
        activeSpeakers[speakerId] = speaker

        // Create and store profile
        val profile = SpeakerProfile(
            id = speakerId,
            embedding = embedding,
            totalSpeakingTime = endTime - startTime,
            segmentCount = 1
        )
        database.storeSpeaker(profile)

        return speaker
    }

    /**
     * Update speaker activity
     */
    private suspend fun updateSpeakerActivity(
        speaker: SpeakerInfo,
        features: AudioFeatures,
        startTime: Double,
        endTime: Double
    ) {
        // Get current profile
        val profile = database.getSpeaker(speaker.id) ?: return

        // Update profile with new activity
        val updatedProfile = profile.copy(
            totalSpeakingTime = profile.totalSpeakingTime + (endTime - startTime),
            segmentCount = profile.segmentCount + 1,
            lastUpdated = System.currentTimeMillis()
        )

        database.updateSpeaker(updatedProfile)
    }

    /**
     * Create silence/no speaker indicator
     */
    private fun createSilenceSpeaker(): SpeakerInfo {
        return SpeakerInfo(
            id = "SILENCE",
            name = "Silence",
            confidence = 1.0f,
            embedding = null
        )
    }

    /**
     * Get all active speakers
     */
    fun getActiveSpeakers(): List<SpeakerInfo> = activeSpeakers.values.toList()

    /**
     * Get speaker profile
     */
    suspend fun getSpeakerProfile(id: String): SpeakerProfile? = database.getSpeaker(id)

    /**
     * Update speaker name
     */
    suspend fun updateSpeakerName(speakerId: String, name: String) {
        // Update active speaker
        activeSpeakers[speakerId]?.let { speaker ->
            activeSpeakers[speakerId] = speaker.copy(name = name)
        }

        // Update profile in database
        database.getSpeaker(speakerId)?.let { profile ->
            database.updateSpeaker(profile.copy(name = name))
        }
    }

    /**
     * Reset all speakers
     */
    suspend fun reset() {
        activeSpeakers.clear()
        database.clearAllSpeakers()
        speakerCounter = 0
    }

    /**
     * Reset only profiles (keep configuration)
     */
    suspend fun resetProfiles() {
        activeSpeakers.clear()
        database.clearAllSpeakers()
    }
}

// MARK: - Transcription Integration

/**
 * Utility class for integrating speaker diarization with STT transcription
 */
object TranscriptionSpeakerIntegrator {
    /**
     * Create labeled transcription from word timestamps and speaker segments
     */
    fun createLabeledTranscription(
        wordTimestamps: List<WordTimestamp>,
        segments: List<SpeakerSegment>,
        speakers: List<SpeakerProfile>
    ): LabeledTranscription {
        val labeledSegments = mutableListOf<LabeledTranscription.LabeledSegment>()

        // Group words by speaker segments
        for (segment in segments) {
            val wordsInSegment = wordTimestamps.filter { word ->
                word.startTime >= segment.startTime && word.endTime <= segment.endTime
            }

            if (wordsInSegment.isNotEmpty()) {
                val text = wordsInSegment.joinToString(" ") { it.word }
                val labeledSegment = LabeledTranscription.LabeledSegment(
                    speakerId = segment.speakerId,
                    text = text,
                    startTime = segment.startTime,
                    endTime = segment.endTime,
                    confidence = segment.confidence
                )
                labeledSegments.add(labeledSegment)
            }
        }

        return LabeledTranscription(
            segments = labeledSegments,
            speakers = speakers
        )
    }

    /**
     * Map transcription text to speaker segments
     */
    fun mapTranscriptionToSpeakers(
        transcriptionText: String,
        segments: List<SpeakerSegment>,
        speakers: List<SpeakerProfile>
    ): LabeledTranscription {
        // Simple text mapping based on segment timing
        // In practice, this would use more sophisticated alignment
        val words = transcriptionText.split(" ")
        val wordsPerSegment = if (segments.isNotEmpty()) words.size / segments.size else 0

        val labeledSegments = segments.mapIndexed { index, segment ->
            val startIndex = index * wordsPerSegment
            val endIndex = minOf((index + 1) * wordsPerSegment, words.size)
            val segmentText = words.subList(startIndex, endIndex).joinToString(" ")

            LabeledTranscription.LabeledSegment(
                speakerId = segment.speakerId,
                text = segmentText,
                startTime = segment.startTime,
                endTime = segment.endTime,
                confidence = segment.confidence
            )
        }

        return LabeledTranscription(
            segments = labeledSegments,
            speakers = speakers
        )
    }
}
