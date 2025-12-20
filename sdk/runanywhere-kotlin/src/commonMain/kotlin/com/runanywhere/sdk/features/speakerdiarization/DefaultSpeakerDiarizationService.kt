package com.runanywhere.sdk.features.speakerdiarization

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.*

/**
 * Default Speaker Diarization Service with energy-based speaker identification
 * Matches iOS DefaultSpeakerDiarization implementation exactly
 */
class DefaultSpeakerDiarizationService(
    private var config: SpeakerDiarizationConfiguration,
    private val database: SpeakerDatabase,
    private val audioProcessor: PlatformAudioProcessor
) : SpeakerDiarizationService {

    // MARK: - Properties

    override var isReady: Boolean = false
        private set

    override val configuration: SpeakerDiarizationConfiguration
        get() = config

    override val currentModel: String?
        get() = config.modelId

    private var speakerManager: SpeakerManager? = null
    private val mutex = Mutex()

    // Audio accumulation for better accuracy
    private val audioAccumulator = mutableListOf<Float>()
    private val minimumChunkDuration: Double = 3.0 // seconds
    private var currentChunkStartTime: Double = 0.0

    // Current speaker tracking
    private var currentSpeaker: SpeakerInfo? = null
    private var speakerSegments = mutableListOf<SpeakerSegment>()
    private var segmentStartTime: Double = 0.0

    // MARK: - Service Lifecycle

    override suspend fun initialize(modelPath: String?) {
        mutex.withLock {
            if (isReady) return

            try {
                // Initialize speaker manager
                speakerManager = SpeakerManager(database, audioProcessor, config)

                // Initialize audio processor (platform-specific)
                // audioProcessor initialization is handled at the platform level

                isReady = true
            } catch (e: Exception) {
                throw SpeakerDiarizationError.ProcessingFailed(e.message ?: "Unknown initialization error")
            }
        }
    }

    override suspend fun cleanup() {
        mutex.withLock {
            speakerManager = null
            audioAccumulator.clear()
            speakerSegments.clear()
            currentSpeaker = null
            isReady = false
        }
    }

    // MARK: - Audio Processing

    override fun processAudio(samples: FloatArray): SpeakerInfo {
        if (!isReady) {
            throw SpeakerDiarizationError.NotInitialized
        }

        val speakerManager = this.speakerManager
            ?: throw SpeakerDiarizationError.NotInitialized

        try {
            // Add samples to accumulator for better analysis
            audioAccumulator.addAll(samples.toList())

            // Calculate current time based on sample count
            val currentTime = audioAccumulator.size.toDouble() / config.sampleRate

            // Check if we have enough samples for processing
            if (currentTime - currentChunkStartTime < minimumChunkDuration) {
                // Return current speaker or silence
                return currentSpeaker ?: createSilenceSpeaker()
            }

            // Process accumulated audio
            val processingSamples = audioAccumulator.toFloatArray()
            val startTime = currentChunkStartTime
            val endTime = currentTime

            // Create embedding and detect speaker
            val embedding = createSimpleEmbedding(processingSamples)
            val detectedSpeaker = findMatchingSpeaker(embedding)
                ?: createNewSpeaker(embedding)

            // Check for speaker change
            if (currentSpeaker?.id != detectedSpeaker.id) {
                // Finalize previous segment
                currentSpeaker?.let { prevSpeaker ->
                    if (prevSpeaker.id != "SILENCE") {
                        val segment = SpeakerSegment(
                            speakerId = prevSpeaker.id,
                            startTime = segmentStartTime,
                            endTime = startTime,
                            confidence = prevSpeaker.confidence ?: 0.8f
                        )
                        speakerSegments.add(segment)
                    }
                }

                // Start new segment
                currentSpeaker = detectedSpeaker
                segmentStartTime = startTime
            }

            // Reset accumulator for next chunk
            audioAccumulator.clear()
            currentChunkStartTime = currentTime

            return detectedSpeaker

        } catch (e: Exception) {
            throw SpeakerDiarizationError.ProcessingFailed(e.message ?: "Audio processing error")
        }
    }

    override suspend fun performDetailedDiarization(
        audioBuffer: FloatArray,
        sampleRate: Int
    ): SpeakerDiarizationResult? {
        if (!isReady) {
            throw SpeakerDiarizationError.NotInitialized
        }

        val startTime = System.currentTimeMillis()

        try {
            val segments = mutableListOf<SpeakerSegment>()
            val speakers = mutableSetOf<SpeakerInfo>()

            // Segment audio into overlapping chunks
            val chunks = audioProcessor.segmentAudio(
                audioBuffer,
                sampleRate,
                config.windowSize,
                config.stepSize
            )

            var currentSpeaker: SpeakerInfo? = null
            var segmentStart = 0.0

            for (chunk in chunks) {
                // Process each chunk
                val embedding = createSimpleEmbedding(chunk.samples)
                val detectedSpeaker = findMatchingSpeaker(embedding)
                    ?: createNewSpeaker(embedding)

                speakers.add(detectedSpeaker)

                // Check for speaker change
                if (currentSpeaker?.id != detectedSpeaker.id) {
                    // Finalize previous segment
                    currentSpeaker?.let { prevSpeaker ->
                        if (prevSpeaker.id != "SILENCE") {
                            val segment = SpeakerSegment(
                                speakerId = prevSpeaker.id,
                                startTime = segmentStart,
                                endTime = chunk.startTime,
                                confidence = prevSpeaker.confidence ?: 0.8f,
                                energy = audioProcessor.calculateRMSEnergy(chunk.samples)
                            )
                            segments.add(segment)
                        }
                    }

                    // Start new segment
                    currentSpeaker = detectedSpeaker
                    segmentStart = chunk.startTime
                }
            }

            // Finalize last segment
            currentSpeaker?.let { speaker ->
                if (speaker.id != "SILENCE" && chunks.isNotEmpty()) {
                    val lastChunk = chunks.last()
                    val segment = SpeakerSegment(
                        speakerId = speaker.id,
                        startTime = segmentStart,
                        endTime = lastChunk.endTime,
                        confidence = speaker.confidence ?: 0.8f,
                        energy = audioProcessor.calculateRMSEnergy(lastChunk.samples)
                    )
                    segments.add(segment)
                }
            }

            val processingTime = (System.currentTimeMillis() - startTime) / 1000.0

            return SpeakerDiarizationResult(
                speakers = speakers.toList(),
                segments = segments,
                processingTime = processingTime,
                confidence = speakers.mapNotNull { it.confidence }.average().toFloat()
            )

        } catch (e: Exception) {
            throw SpeakerDiarizationError.ProcessingFailed(e.message ?: "Detailed diarization error")
        }
    }

    // MARK: - Speaker Management

    override fun getAllSpeakers(): List<SpeakerInfo> {
        return speakerManager?.getActiveSpeakers() ?: emptyList()
    }

    override fun getSpeakerProfile(id: String): SpeakerProfile? {
        // This would need to be suspended, but interface doesn't allow it
        // In practice, we'd cache profiles or use a different approach
        return null // TODO: Implement with cached profiles
    }

    override fun updateSpeakerName(speakerId: String, name: String) {
        // Update would need to be suspended for database access
        // For now, update in-memory only
        speakerManager?.let { manager ->
            // We'd need to make this suspend and call the suspend version
            // For now, this is a placeholder
        }
    }

    override fun reset() {
        audioAccumulator.clear()
        speakerSegments.clear()
        currentSpeaker = null
        segmentStartTime = 0.0
        currentChunkStartTime = 0.0

        // Reset speaker manager (would need suspend)
        // speakerManager?.reset()
    }

    override fun resetProfiles() {
        // Would need suspend for database operations
        // speakerManager?.resetProfiles()
    }

    // MARK: - Private Methods - Energy-based Speaker Identification

    /**
     * Create simple embedding from audio buffer using energy-based features
     * Matches iOS DefaultSpeakerDiarization.createSimpleEmbedding exactly
     */
    private fun createSimpleEmbedding(audioBuffer: FloatArray): FloatArray {
        val embeddingSize = config.embeddingSize
        val embedding = FloatArray(embeddingSize)

        if (audioBuffer.isEmpty()) {
            return embedding
        }

        val chunkSize = max(1, audioBuffer.size / embeddingSize)

        for (i in 0 until min(embeddingSize, audioBuffer.size / chunkSize)) {
            val start = i * chunkSize
            val end = min(start + chunkSize, audioBuffer.size)
            val chunk = audioBuffer.sliceArray(start until end)

            if (chunk.isNotEmpty()) {
                // Calculate mean and variance for this chunk
                val mean = chunk.average().toFloat()
                val variance = chunk.map { (it - mean).pow(2) }.average().toFloat()

                // Combine mean and variance as in iOS implementation
                embedding[i] = mean + sqrt(variance)
            }
        }

        return embedding
    }

    /**
     * Calculate cosine similarity between two embeddings
     * Uses the same algorithm as iOS implementation
     */
    private fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size) return 0.0f

        return audioProcessor.cosineSimilarity(a, b)
    }

    /**
     * Find matching speaker based on embedding similarity
     * Matches iOS DefaultSpeakerDiarization.findMatchingSpeaker exactly
     */
    private fun findMatchingSpeaker(embedding: FloatArray): SpeakerInfo? {
        val speakers = getAllSpeakers()
        var bestMatch: Pair<SpeakerInfo, Float>? = null

        for (speaker in speakers) {
            speaker.embedding?.let { speakerEmbedding ->
                val similarity = cosineSimilarity(embedding, speakerEmbedding)
                if (similarity > config.speakerChangeThreshold) {
                    if (bestMatch == null || similarity > bestMatch!!.second) {
                        bestMatch = speaker to similarity
                    }
                }
            }
        }

        return bestMatch?.first
    }

    /**
     * Create new speaker with given embedding
     * Matches iOS DefaultSpeakerDiarization.createNewSpeaker exactly
     */
    private fun createNewSpeaker(embedding: FloatArray): SpeakerInfo {
        val currentSpeakers = getAllSpeakers()
        val speakerCount = currentSpeakers.count { !it.id.startsWith("SILENCE") }

        // Check max speakers limit
        if (speakerCount >= config.maxSpeakers) {
            // Return most similar existing speaker instead of creating new one
            return currentSpeakers.firstOrNull { !it.id.startsWith("SILENCE") }
                ?: createSilenceSpeaker()
        }

        val speakerId = "Speaker_${speakerCount + 1}"
        return SpeakerInfo(
            id = speakerId,
            name = null, // Will be assigned later
            confidence = 0.8f, // Default confidence for new speakers
            embedding = embedding,
            createdAt = getCurrentTimeMillis()
        )
    }

    /**
     * Create silence/no speaker indicator
     */
    private fun createSilenceSpeaker(): SpeakerInfo {
        return SpeakerInfo(
            id = "SILENCE",
            name = "Silence",
            confidence = 1.0f,
            embedding = null,
            createdAt = getCurrentTimeMillis()
        )
    }

    // MARK: - Audio Analysis Utilities

    /**
     * Calculate RMS energy of audio samples
     * Uses the same algorithm as iOS for consistency
     */
    private fun calculateRMSEnergy(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0.0f

        val sumSquares = samples.map { it * it }.sum()
        return sqrt(sumSquares / samples.size)
    }

    /**
     * Check if audio contains speech based on energy threshold
     */
    private fun containsSpeech(samples: FloatArray): Boolean {
        val energy = calculateRMSEnergy(samples)
        return energy > config.energyThreshold
    }

    /**
     * Detect speaker change based on embedding similarity
     */
    private fun detectSpeakerChange(
        currentEmbedding: FloatArray?,
        newEmbedding: FloatArray
    ): Boolean {
        currentEmbedding?.let { current ->
            val similarity = cosineSimilarity(current, newEmbedding)
            return similarity < config.speakerChangeThreshold
        }
        return true // First speaker or no previous embedding
    }
}

// MARK: - In-Memory Speaker Database

/**
 * Simple in-memory speaker database for DefaultSpeakerDiarizationService
 */
class InMemorySpeakerDatabase : SpeakerDatabase {
    private val speakers = mutableMapOf<String, SpeakerProfile>()
    private val mutex = Mutex()

    override suspend fun storeSpeaker(profile: SpeakerProfile) {
        mutex.withLock {
            speakers[profile.id] = profile
        }
    }

    override suspend fun getSpeaker(id: String): SpeakerProfile? {
        return mutex.withLock {
            speakers[id]
        }
    }

    override suspend fun getAllSpeakers(): List<SpeakerProfile> {
        return mutex.withLock {
            speakers.values.toList()
        }
    }

    override suspend fun updateSpeaker(profile: SpeakerProfile) {
        mutex.withLock {
            speakers[profile.id] = profile
        }
    }

    override suspend fun deleteSpeaker(id: String) {
        mutex.withLock {
            speakers.remove(id)
        }
    }

    override suspend fun clearAllSpeakers() {
        mutex.withLock {
            speakers.clear()
        }
    }

    override suspend fun findSimilarSpeakers(
        embedding: FloatArray,
        threshold: Float
    ): List<Pair<SpeakerProfile, Float>> {
        return mutex.withLock {
            val processor = PlatformAudioProcessor() // Platform-specific instance
            speakers.values.mapNotNull { profile ->
                profile.embedding?.let { profileEmbedding ->
                    val similarity = processor.cosineSimilarity(embedding, profileEmbedding)
                    if (similarity > threshold) {
                        profile to similarity
                    } else null
                }
            }.sortedByDescending { it.second }
        }
    }
}
