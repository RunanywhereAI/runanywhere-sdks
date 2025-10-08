# Module 4: Speaker Diarization Implementation Plan
**Priority**: 🔴 CRITICAL/EMERGENCY
**Estimated Timeline**: 10-12 days
**Dependencies**: Module 2 (STT) for audio processing foundation
**Team Assignment**: 2 Developers (1 Senior + 1 ML Engineer)

## 🚨 EMERGENCY STATUS ALERT

**CRITICAL BUSINESS GAP**: Speaker diarization is completely missing from the Kotlin SDK while being a core production feature in iOS. This represents a **major competitive disadvantage** and **feature parity failure**.

**Current Status**: 0% implemented - No code, no interfaces, no design
**iOS Status**: 100% production-ready with 584-line implementation
**Business Impact**: HIGH - Core voice feature missing

---

## Executive Summary

Speaker diarization (speaker identification and conversation attribution) is a **missing critical feature** that needs immediate emergency implementation. The iOS SDK has a complete, sophisticated implementation while the Kotlin SDK has absolutely nothing - not even interface stubs.

**What Speaker Diarization Provides**:
- Identifies different speakers in audio conversations
- Attributes each speech segment to a specific speaker
- Creates speaker profiles and voice embeddings
- Enables multi-speaker conversation transcription
- Powers advanced voice assistant features

**Why This is Emergency Priority**:
1. **Feature Parity Violation**: Major iOS feature completely missing
2. **Business Critical**: Core voice capability expected by users
3. **Competitive Disadvantage**: Limits voice assistant capabilities
4. **Technical Debt**: Will become harder to implement later

---

## Current State Analysis

### ❌ Complete Absence of Implementation
- No `SpeakerDiarizationComponent` class
- No speaker data models (SpeakerInfo, SpeakerProfile)
- No speaker embedding or identification algorithms
- No integration with STT for labeled transcription
- No speaker voice profile management
- No multi-speaker conversation support

### ✅ iOS Implementation for Reference
The iOS implementation provides:
- Complete speaker identification pipeline
- Voice embedding extraction and comparison
- Speaker profile creation and management
- Integration with STT for speaker-labeled transcription
- Advanced speaker clustering algorithms
- Real-time speaker switching detection

### 🎯 Implementation Target
Build complete speaker diarization system matching iOS capabilities:
- Real-time speaker identification during conversations
- Speaker profile creation and voice learning
- Multi-speaker conversation transcription with labels
- Voice embedding extraction and comparison
- Speaker clustering and identification algorithms

---

## Phase 1: Foundation Architecture (Day 1-3)
**Duration**: 3 days
**Priority**: CRITICAL

### Task 1.1: Speaker Data Models Design
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/`

#### Core Data Models
```kotlin
// Speaker identification and profile models
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float,
    val voiceEmbedding: FloatArray,
    val profileCreationTime: Long = System.currentTimeMillis(),
    val lastSeenTime: Long = System.currentTimeMillis(),
    val totalSpeechDuration: Long = 0L,
    val averageConfidence: Float = confidence
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerInfo) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

data class SpeakerProfile(
    val speakerId: String,
    val name: String? = null,
    val voiceEmbeddings: List<FloatArray>,
    val characteristics: VoiceCharacteristics,
    val creationTime: Long,
    val updateTime: Long,
    val sampleCount: Int,
    val confidenceHistory: List<Float>
) {
    val averageEmbedding: FloatArray by lazy {
        if (voiceEmbeddings.isEmpty()) floatArrayOf()
        else {
            val embeddingSize = voiceEmbeddings.first().size
            val result = FloatArray(embeddingSize)

            voiceEmbeddings.forEach { embedding ->
                embedding.forEachIndexed { index, value ->
                    result[index] += value
                }
            }

            result.forEachIndexed { index, value ->
                result[index] = value / voiceEmbeddings.size
            }

            result
        }
    }
}

data class VoiceCharacteristics(
    val fundamentalFrequency: Float, // F0 - pitch
    val formantFrequencies: FloatArray, // F1, F2, F3
    val spectralCentroid: Float,
    val zeroCrossingRate: Float,
    val mfccCoefficients: FloatArray, // Mel-frequency cepstral coefficients
    val energyDistribution: FloatArray
)

data class SpeechSegment(
    val startTime: Long, // milliseconds
    val endTime: Long,   // milliseconds
    val speakerId: String,
    val confidence: Float,
    val text: String? = null,
    val audioData: ByteArray? = null,
    val voiceEmbedding: FloatArray? = null
) {
    val duration: Long get() = endTime - startTime
}

data class DiarizationResult(
    val segments: List<SpeechSegment>,
    val speakers: List<SpeakerInfo>,
    val overallConfidence: Float,
    val processingTimeMs: Long,
    val metadata: Map<String, Any> = emptyMap()
) {
    val uniqueSpeakerCount: Int get() = speakers.distinctBy { it.id }.size
    val totalDuration: Long get() = segments.maxOfOrNull { it.endTime } ?: 0L
}

data class SpeakerIdentificationResult(
    val speakerId: String,
    val confidence: Float,
    val voiceEmbedding: FloatArray,
    val matchedProfile: SpeakerProfile?,
    val isNewSpeaker: Boolean,
    val similarityScores: Map<String, Float> // speakerId to similarity score
)

// Configuration classes
data class SpeakerDiarizationConfiguration(
    val enableRealTimeProcessing: Boolean = true,
    val minimumSegmentDuration: Long = 500, // milliseconds
    val maxSpeakers: Int = 10,
    val similarityThreshold: Float = 0.75f,
    val voiceEmbeddingSize: Int = 512,
    val enableSpeakerLearning: Boolean = true,
    val confidenceThreshold: Float = 0.6f,
    val segmentationWindowSize: Int = 1024,
    val overlapRatio: Float = 0.5f
) : ComponentConfiguration {
    override fun validate() {
        require(minimumSegmentDuration > 0) { "Minimum segment duration must be positive" }
        require(maxSpeakers > 0) { "Max speakers must be positive" }
        require(similarityThreshold in 0f..1f) { "Similarity threshold must be between 0 and 1" }
        require(confidenceThreshold in 0f..1f) { "Confidence threshold must be between 0 and 1" }
        require(voiceEmbeddingSize > 0) { "Voice embedding size must be positive" }
    }
}
```

### Task 1.2: Service Interface Design
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/SpeakerDiarizationService.kt`

```kotlin
interface SpeakerDiarizationService {
    /**
     * Initialize the speaker diarization service
     */
    suspend fun initialize(): Boolean

    /**
     * Process audio data and perform speaker diarization
     */
    suspend fun processAudio(audioData: ByteArray): DiarizationResult

    /**
     * Process audio with existing STT transcription
     */
    suspend fun processAudioWithTranscription(
        audioData: ByteArray,
        transcription: String,
        timestamps: List<TimestampInfo>
    ): DiarizationResult

    /**
     * Create or update a speaker profile from audio samples
     */
    suspend fun createSpeakerProfile(
        speakerId: String,
        audioSamples: List<ByteArray>,
        name: String? = null
    ): SpeakerProfile

    /**
     * Identify speaker in audio segment
     */
    suspend fun identifySpeaker(audioData: ByteArray): SpeakerIdentificationResult

    /**
     * Extract voice embedding from audio
     */
    suspend fun extractVoiceEmbedding(audioData: ByteArray): FloatArray

    /**
     * Calculate similarity between two voice embeddings
     */
    fun calculateSimilarity(embedding1: FloatArray, embedding2: FloatArray): Float

    /**
     * Get all known speaker profiles
     */
    suspend fun getSpeakerProfiles(): List<SpeakerProfile>

    /**
     * Update existing speaker profile with new audio sample
     */
    suspend fun updateSpeakerProfile(speakerId: String, audioData: ByteArray): Boolean

    /**
     * Delete speaker profile
     */
    suspend fun deleteSpeakerProfile(speakerId: String): Boolean

    /**
     * Process streaming audio for real-time diarization
     */
    fun processAudioStream(audioStream: Flow<ByteArray>): Flow<SpeechSegment>

    /**
     * Cleanup resources
     */
    fun cleanup()

    /**
     * Service state
     */
    val isReady: Boolean
    val supportedAudioFormats: List<String>
    val maxSupportedSpeakers: Int
}
```

### Task 1.3: Component Architecture
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/SpeakerDiarizationComponent.kt`

```kotlin
class SpeakerDiarizationComponent(
    configuration: SpeakerDiarizationConfiguration,
    serviceContainer: ServiceContainer? = null
) : BaseComponent<SpeakerDiarizationService>(configuration, serviceContainer) {

    companion object {
        override val componentType: SDKComponent = SDKComponent.SPEAKER_DIARIZATION
    }

    private val diarizationConfig = configuration as SpeakerDiarizationConfiguration

    override suspend fun createService(): SpeakerDiarizationService {
        val provider = ModuleRegistry.speakerDiarizationProvider()
            ?: throw SDKError.ComponentNotAvailable("No speaker diarization provider available")

        return provider.createSpeakerDiarizationService(diarizationConfig)
    }

    /**
     * High-level diarization with STT integration
     */
    suspend fun diarizeWithTranscription(audioData: ByteArray): DiarizationWithText {
        ensureReady()

        return try {
            updateState(ComponentState.PROCESSING)

            // Get STT transcription first
            val sttComponent = serviceContainer?.sttComponent
                ?: throw SDKError.ComponentNotAvailable("STT component required for transcription")

            val transcriptionResult = sttComponent.transcribe(audioData)

            // Perform diarization
            val diarizationResult = service!!.processAudioWithTranscription(
                audioData = audioData,
                transcription = transcriptionResult.transcript,
                timestamps = transcriptionResult.segments
            )

            // Combine results
            val labeledTranscript = createLabeledTranscript(
                transcriptionResult.segments,
                diarizationResult.segments
            )

            updateState(ComponentState.READY)

            DiarizationWithText(
                diarizationResult = diarizationResult,
                originalTranscription = transcriptionResult,
                labeledTranscript = labeledTranscript
            )

        } catch (e: Exception) {
            updateState(ComponentState.FAILED)
            throw SDKError.ComponentProcessingFailed("Speaker diarization failed", e)
        }
    }

    /**
     * Real-time streaming diarization
     */
    fun streamDiarization(
        audioStream: Flow<ByteArray>
    ): Flow<SpeakerDiarizationEvent> = flow {
        ensureReady()

        service!!.processAudioStream(audioStream).collect { segment ->
            emit(SpeakerDiarizationEvent.SpeakerSegment(segment))

            // Emit speaker change events
            // This would track speaker transitions
        }
    }

    /**
     * Speaker learning and profile management
     */
    suspend fun learnSpeaker(
        name: String,
        audioSamples: List<ByteArray>
    ): SpeakerProfile {
        ensureReady()

        val speakerId = generateSpeakerId(name)
        return service!!.createSpeakerProfile(speakerId, audioSamples, name)
    }

    private fun createLabeledTranscript(
        transcriptionSegments: List<TimestampInfo>,
        diarizationSegments: List<SpeechSegment>
    ): List<LabeledTranscriptSegment> {
        return transcriptionSegments.mapNotNull { transcriptSegment ->
            // Find matching diarization segment
            val matchingDiarization = diarizationSegments.find { diarizationSegment ->
                timeSegmentsOverlap(
                    transcriptSegment.startTime,
                    transcriptSegment.endTime,
                    diarizationSegment.startTime,
                    diarizationSegment.endTime
                )
            }

            matchingDiarization?.let { diarization ->
                LabeledTranscriptSegment(
                    text = transcriptSegment.text,
                    startTime = transcriptSegment.startTime,
                    endTime = transcriptSegment.endTime,
                    speakerId = diarization.speakerId,
                    confidence = (transcriptSegment.confidence + diarization.confidence) / 2f
                )
            }
        }
    }

    private fun timeSegmentsOverlap(
        start1: Long, end1: Long,
        start2: Long, end2: Long
    ): Boolean {
        return start1 < end2 && start2 < end1
    }

    private fun generateSpeakerId(name: String): String {
        return "speaker_${name.lowercase().replace(" ", "_")}_${System.currentTimeMillis()}"
    }
}

// Additional data classes for component integration
data class DiarizationWithText(
    val diarizationResult: DiarizationResult,
    val originalTranscription: TranscriptionResult,
    val labeledTranscript: List<LabeledTranscriptSegment>
)

data class LabeledTranscriptSegment(
    val text: String,
    val startTime: Long,
    val endTime: Long,
    val speakerId: String,
    val confidence: Float
)

sealed class SpeakerDiarizationEvent {
    data class SpeakerSegment(val segment: SpeechSegment) : SpeakerDiarizationEvent()
    data class SpeakerChanged(val newSpeakerId: String, val previousSpeakerId: String?) : SpeakerDiarizationEvent()
    data class NewSpeakerDetected(val speakerId: String, val confidence: Float) : SpeakerDiarizationEvent()
    data class ProcessingError(val error: Throwable) : SpeakerDiarizationEvent()
}
```

**Success Criteria**:
- [ ] Complete data model architecture for speaker diarization
- [ ] Service interface covers all required functionality
- [ ] Component integrates with existing BaseComponent architecture
- [ ] STT integration patterns are defined
- [ ] Event system supports real-time diarization

---

## Phase 2: Core Algorithm Implementation (Day 4-7)
**Duration**: 4 days
**Priority**: CRITICAL

### Task 2.1: Voice Embedding Extraction
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/algorithms/`

```kotlin
// Voice feature extraction for speaker identification
class VoiceEmbeddingExtractor {

    /**
     * Extract MFCC (Mel-Frequency Cepstral Coefficients) features
     */
    fun extractMFCC(audioData: FloatArray, sampleRate: Int): FloatArray {
        val windowSize = 512
        val hopSize = 256
        val numMelFilters = 26
        val numMFCC = 13

        // Pre-emphasis filter
        val preEmphasized = applyPreEmphasis(audioData)

        // Windowing and FFT
        val spectrograms = computeSpectrogram(preEmphasized, windowSize, hopSize)

        // Mel filter bank
        val melSpectrograms = applyMelFilterBank(spectrograms, sampleRate, numMelFilters)

        // DCT to get MFCC
        val mfccFeatures = applyDCT(melSpectrograms, numMFCC)

        // Feature normalization
        return normalizeMFCC(mfccFeatures)
    }

    /**
     * Extract voice embedding combining multiple features
     */
    fun extractVoiceEmbedding(audioData: ByteArray): FloatArray {
        val floatAudio = convertBytesToFloat(audioData)
        val sampleRate = 16000 // Assuming 16kHz

        // Extract different feature types
        val mfccFeatures = extractMFCC(floatAudio, sampleRate)
        val spectralFeatures = extractSpectralFeatures(floatAudio, sampleRate)
        val prosodyFeatures = extractProsodyFeatures(floatAudio, sampleRate)

        // Combine features into single embedding
        return combineFeatures(mfccFeatures, spectralFeatures, prosodyFeatures)
    }

    private fun extractSpectralFeatures(audio: FloatArray, sampleRate: Int): FloatArray {
        val spectralCentroid = calculateSpectralCentroid(audio, sampleRate)
        val spectralRolloff = calculateSpectralRolloff(audio, sampleRate)
        val zeroCrossingRate = calculateZeroCrossingRate(audio)
        val spectralFlux = calculateSpectralFlux(audio)

        return floatArrayOf(spectralCentroid, spectralRolloff, zeroCrossingRate, spectralFlux)
    }

    private fun extractProsodyFeatures(audio: FloatArray, sampleRate: Int): FloatArray {
        val fundamentalFreq = extractFundamentalFrequency(audio, sampleRate)
        val energy = calculateRMSEnergy(audio)
        val tonality = calculateTonality(audio)

        return floatArrayOf(fundamentalFreq, energy, tonality)
    }

    private fun combineFeatures(vararg featureArrays: FloatArray): FloatArray {
        val totalSize = featureArrays.sumOf { it.size }
        val combined = FloatArray(totalSize)
        var offset = 0

        featureArrays.forEach { features ->
            System.arraycopy(features, 0, combined, offset, features.size)
            offset += features.size
        }

        // Apply dimensionality reduction if needed (PCA)
        return if (combined.size > 512) {
            applyPCA(combined, targetDimensions = 512)
        } else {
            combined
        }
    }

    // Audio processing utility functions
    private fun applyPreEmphasis(audio: FloatArray, alpha: Float = 0.97f): FloatArray {
        val result = FloatArray(audio.size)
        result[0] = audio[0]

        for (i in 1 until audio.size) {
            result[i] = audio[i] - alpha * audio[i - 1]
        }

        return result
    }

    private fun computeSpectrogram(audio: FloatArray, windowSize: Int, hopSize: Int): Array<FloatArray> {
        val numFrames = (audio.size - windowSize) / hopSize + 1
        val spectrogram = Array(numFrames) { FloatArray(windowSize / 2 + 1) }

        val window = hammingWindow(windowSize)
        val fft = FFT(windowSize)

        for (frame in 0 until numFrames) {
            val start = frame * hopSize
            val frameData = FloatArray(windowSize)

            for (i in 0 until windowSize) {
                frameData[i] = audio[start + i] * window[i]
            }

            val fftResult = fft.forward(frameData)
            spectrogram[frame] = fftResult.magnitude()
        }

        return spectrogram
    }

    private fun calculateSpectralCentroid(audio: FloatArray, sampleRate: Int): Float {
        // Implementation of spectral centroid calculation
        val spectrum = FFT(audio.size).forward(audio)
        val magnitude = spectrum.magnitude()

        var weightedSum = 0f
        var totalMagnitude = 0f

        for (i in magnitude.indices) {
            val frequency = i * sampleRate.toFloat() / audio.size
            weightedSum += frequency * magnitude[i]
            totalMagnitude += magnitude[i]
        }

        return if (totalMagnitude > 0) weightedSum / totalMagnitude else 0f
    }

    private fun extractFundamentalFrequency(audio: FloatArray, sampleRate: Int): Float {
        // Autocorrelation-based pitch detection
        val minPeriod = sampleRate / 800 // Max 800Hz
        val maxPeriod = sampleRate / 80  // Min 80Hz

        var maxCorrelation = 0f
        var bestPeriod = minPeriod

        for (period in minPeriod..maxPeriod) {
            var correlation = 0f
            for (i in 0 until audio.size - period) {
                correlation += audio[i] * audio[i + period]
            }

            if (correlation > maxCorrelation) {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }

        return sampleRate.toFloat() / bestPeriod
    }
}
```

### Task 2.2: Speaker Clustering and Identification
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/algorithms/SpeakerClustering.kt`

```kotlin
class SpeakerClustering {

    /**
     * Cluster speech segments by speaker using voice embeddings
     */
    fun clusterSpeakers(
        segments: List<SpeechSegment>,
        maxSpeakers: Int,
        similarityThreshold: Float = 0.75f
    ): List<SpeakerCluster> {
        if (segments.isEmpty()) return emptyList()

        // Initialize clusters
        val clusters = mutableListOf<SpeakerCluster>()

        segments.forEach { segment ->
            val embedding = segment.voiceEmbedding
                ?: throw IllegalArgumentException("Segment must have voice embedding")

            // Find best matching cluster
            val bestCluster = findBestCluster(embedding, clusters, similarityThreshold)

            if (bestCluster != null) {
                // Add to existing cluster
                bestCluster.addSegment(segment)
            } else if (clusters.size < maxSpeakers) {
                // Create new cluster
                val newCluster = SpeakerCluster(generateClusterId(), embedding)
                newCluster.addSegment(segment)
                clusters.add(newCluster)
            } else {
                // Force assignment to best available cluster
                val forcedCluster = clusters.maxByOrNull { cluster ->
                    calculateEmbeddingSimilarity(embedding, cluster.centroidEmbedding)
                }
                forcedCluster?.addSegment(segment)
            }
        }

        return clusters
    }

    /**
     * Identify speaker for new audio segment
     */
    fun identifySpeaker(
        voiceEmbedding: FloatArray,
        knownSpeakers: List<SpeakerProfile>,
        threshold: Float = 0.75f
    ): SpeakerIdentificationResult {
        if (knownSpeakers.isEmpty()) {
            val newSpeakerId = generateNewSpeakerId()
            return SpeakerIdentificationResult(
                speakerId = newSpeakerId,
                confidence = 1.0f,
                voiceEmbedding = voiceEmbedding,
                matchedProfile = null,
                isNewSpeaker = true,
                similarityScores = emptyMap()
            )
        }

        val similarityScores = mutableMapOf<String, Float>()
        var bestMatch: SpeakerProfile? = null
        var bestSimilarity = 0f

        knownSpeakers.forEach { speaker ->
            val similarity = calculateEmbeddingSimilarity(voiceEmbedding, speaker.averageEmbedding)
            similarityScores[speaker.speakerId] = similarity

            if (similarity > bestSimilarity) {
                bestSimilarity = similarity
                bestMatch = speaker
            }
        }

        return if (bestSimilarity >= threshold && bestMatch != null) {
            // Match found
            SpeakerIdentificationResult(
                speakerId = bestMatch.speakerId,
                confidence = bestSimilarity,
                voiceEmbedding = voiceEmbedding,
                matchedProfile = bestMatch,
                isNewSpeaker = false,
                similarityScores = similarityScores
            )
        } else {
            // New speaker
            val newSpeakerId = generateNewSpeakerId()
            SpeakerIdentificationResult(
                speakerId = newSpeakerId,
                confidence = 1.0f - bestSimilarity, // Confidence in being new
                voiceEmbedding = voiceEmbedding,
                matchedProfile = null,
                isNewSpeaker = true,
                similarityScores = similarityScores
            )
        }
    }

    /**
     * Calculate similarity between two voice embeddings
     */
    fun calculateEmbeddingSimilarity(embedding1: FloatArray, embedding2: FloatArray): Float {
        require(embedding1.size == embedding2.size) {
            "Embeddings must have same size: ${embedding1.size} vs ${embedding2.size}"
        }

        // Cosine similarity
        var dotProduct = 0f
        var norm1 = 0f
        var norm2 = 0f

        for (i in embedding1.indices) {
            dotProduct += embedding1[i] * embedding2[i]
            norm1 += embedding1[i] * embedding1[i]
            norm2 += embedding2[i] * embedding2[i]
        }

        val magnitude1 = sqrt(norm1)
        val magnitude2 = sqrt(norm2)

        return if (magnitude1 > 0f && magnitude2 > 0f) {
            dotProduct / (magnitude1 * magnitude2)
        } else {
            0f
        }
    }

    private fun findBestCluster(
        embedding: FloatArray,
        clusters: List<SpeakerCluster>,
        threshold: Float
    ): SpeakerCluster? {
        var bestCluster: SpeakerCluster? = null
        var bestSimilarity = 0f

        clusters.forEach { cluster ->
            val similarity = calculateEmbeddingSimilarity(embedding, cluster.centroidEmbedding)
            if (similarity > bestSimilarity && similarity >= threshold) {
                bestSimilarity = similarity
                bestCluster = cluster
            }
        }

        return bestCluster
    }

    private fun generateClusterId(): String = "cluster_${System.currentTimeMillis()}_${Random.nextInt(1000)}"
    private fun generateNewSpeakerId(): String = "speaker_${System.currentTimeMillis()}_${Random.nextInt(1000)}"
}

data class SpeakerCluster(
    val id: String,
    private var _centroidEmbedding: FloatArray
) {
    private val _segments = mutableListOf<SpeechSegment>()
    val segments: List<SpeechSegment> get() = _segments.toList()
    val centroidEmbedding: FloatArray get() = _centroidEmbedding

    fun addSegment(segment: SpeechSegment) {
        _segments.add(segment)
        updateCentroid()
    }

    private fun updateCentroid() {
        if (_segments.isEmpty()) return

        val embeddingSize = _centroidEmbedding.size
        val newCentroid = FloatArray(embeddingSize)

        _segments.forEach { segment ->
            segment.voiceEmbedding?.let { embedding ->
                for (i in 0 until embeddingSize) {
                    newCentroid[i] += embedding[i]
                }
            }
        }

        // Average the embeddings
        for (i in 0 until embeddingSize) {
            newCentroid[i] /= _segments.size
        }

        _centroidEmbedding = newCentroid
    }
}
```

### Task 2.3: Audio Segmentation and VAD Integration
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/algorithms/AudioSegmentation.kt`

```kotlin
class AudioSegmentation {

    /**
     * Segment audio into speech segments using VAD and change point detection
     */
    fun segmentAudio(
        audioData: ByteArray,
        vadService: VADService,
        minimumSegmentDuration: Long = 500 // milliseconds
    ): List<AudioSegment> {
        val floatAudio = convertBytesToFloat(audioData)
        val sampleRate = 16000

        // Apply VAD to find speech regions
        val speechRegions = findSpeechRegions(floatAudio, vadService, sampleRate)

        // Apply speaker change detection within speech regions
        val segments = mutableListOf<AudioSegment>()

        speechRegions.forEach { region ->
            val regionAudio = floatAudio.sliceArray(region.startSample until region.endSample)
            val changePoints = detectSpeakerChangePoints(regionAudio, sampleRate)

            // Create segments based on change points
            var segmentStart = region.startSample

            changePoints.forEach { changePoint ->
                val segmentEnd = region.startSample + changePoint

                if ((segmentEnd - segmentStart) * 1000 / sampleRate >= minimumSegmentDuration) {
                    segments.add(
                        AudioSegment(
                            startTime = (segmentStart * 1000L) / sampleRate,
                            endTime = (segmentEnd * 1000L) / sampleRate,
                            startSample = segmentStart,
                            endSample = segmentEnd,
                            audioData = floatAudio.sliceArray(segmentStart until segmentEnd)
                        )
                    )
                }

                segmentStart = segmentEnd
            }

            // Add final segment
            if ((region.endSample - segmentStart) * 1000 / sampleRate >= minimumSegmentDuration) {
                segments.add(
                    AudioSegment(
                        startTime = (segmentStart * 1000L) / sampleRate,
                        endTime = (region.endSample * 1000L) / sampleRate,
                        startSample = segmentStart,
                        endSample = region.endSample,
                        audioData = floatAudio.sliceArray(segmentStart until region.endSample)
                    )
                )
            }
        }

        return segments
    }

    /**
     * Detect speaker change points within audio using spectral features
     */
    private fun detectSpeakerChangePoints(audio: FloatArray, sampleRate: Int): List<Int> {
        val windowSize = sampleRate / 4 // 250ms windows
        val hopSize = windowSize / 4    // 75% overlap
        val changePoints = mutableListOf<Int>()

        if (audio.size < windowSize * 2) return changePoints

        val features = mutableListOf<FloatArray>()

        // Extract features for each window
        var windowStart = 0
        while (windowStart + windowSize < audio.size) {
            val window = audio.sliceArray(windowStart until windowStart + windowSize)
            val mfcc = extractMFCCForWindow(window, sampleRate)
            features.add(mfcc)
            windowStart += hopSize
        }

        // Detect change points using distance metric
        val threshold = calculateAdaptiveThreshold(features)

        for (i in 1 until features.size - 1) {
            val prevFeature = features[i - 1]
            val currentFeature = features[i]
            val nextFeature = features[i + 1]

            val distancePrev = calculateFeatureDistance(prevFeature, currentFeature)
            val distanceNext = calculateFeatureDistance(currentFeature, nextFeature)

            // Peak detection for change points
            if (distancePrev > threshold && distanceNext > threshold) {
                val changePointSample = i * hopSize
                changePoints.add(changePointSample)
            }
        }

        return changePoints
    }

    private fun findSpeechRegions(
        audio: FloatArray,
        vadService: VADService,
        sampleRate: Int
    ): List<SpeechRegion> {
        val regions = mutableListOf<SpeechRegion>()
        val frameSize = sampleRate / 100 // 10ms frames

        var inSpeech = false
        var speechStart = 0

        for (frameStart in 0 until audio.size step frameSize) {
            val frameEnd = minOf(frameStart + frameSize, audio.size)
            val frame = audio.sliceArray(frameStart until frameEnd)

            val isSpeech = vadService.processAudioData(frame)

            if (isSpeech && !inSpeech) {
                // Speech started
                speechStart = frameStart
                inSpeech = true
            } else if (!isSpeech && inSpeech) {
                // Speech ended
                regions.add(SpeechRegion(speechStart, frameStart))
                inSpeech = false
            }
        }

        // Handle case where speech continues to end
        if (inSpeech) {
            regions.add(SpeechRegion(speechStart, audio.size))
        }

        return regions
    }

    private fun calculateFeatureDistance(feature1: FloatArray, feature2: FloatArray): Float {
        require(feature1.size == feature2.size)

        var sumSquaredDiff = 0f
        for (i in feature1.indices) {
            val diff = feature1[i] - feature2[i]
            sumSquaredDiff += diff * diff
        }

        return sqrt(sumSquaredDiff)
    }

    private fun calculateAdaptiveThreshold(features: List<FloatArray>): Float {
        if (features.size < 2) return 0f

        val distances = mutableListOf<Float>()

        for (i in 1 until features.size) {
            val distance = calculateFeatureDistance(features[i - 1], features[i])
            distances.add(distance)
        }

        val mean = distances.average().toFloat()
        val variance = distances.map { (it - mean) * (it - mean) }.average().toFloat()
        val stdDev = sqrt(variance)

        // Threshold = mean + 2 * standard deviation
        return mean + 2 * stdDev
    }
}

data class AudioSegment(
    val startTime: Long,    // milliseconds
    val endTime: Long,      // milliseconds
    val startSample: Int,   // sample index
    val endSample: Int,     // sample index
    val audioData: FloatArray
)

data class SpeechRegion(
    val startSample: Int,
    val endSample: Int
)
```

**Success Criteria**:
- [ ] Voice embedding extraction produces consistent embeddings
- [ ] Speaker clustering accurately groups same-speaker segments
- [ ] Speaker identification works with reasonable accuracy
- [ ] Audio segmentation produces meaningful speech segments
- [ ] Integration with VAD service works properly

---

## Phase 3: Service Implementation (Day 8-10)
**Duration**: 3 days
**Priority**: HIGH

### Task 3.1: Complete Service Implementation
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/DefaultSpeakerDiarizationService.kt`

```kotlin
class DefaultSpeakerDiarizationService(
    private val configuration: SpeakerDiarizationConfiguration
) : SpeakerDiarizationService {

    private val embeddingExtractor = VoiceEmbeddingExtractor()
    private val speakerClustering = SpeakerClustering()
    private val audioSegmentation = AudioSegmentation()
    private val speakerProfileRepository = SpeakerProfileRepository()

    private var isInitialized = false
    private val logger = SDKLogger.getLogger("SpeakerDiarizationService")

    override suspend fun initialize(): Boolean {
        return try {
            // Initialize any ML models or resources
            speakerProfileRepository.initialize()
            isInitialized = true
            logger.info("Speaker diarization service initialized successfully")
            true
        } catch (e: Exception) {
            logger.error("Failed to initialize speaker diarization service", e)
            false
        }
    }

    override suspend fun processAudio(audioData: ByteArray): DiarizationResult =
        withContext(Dispatchers.IO) {
            require(isInitialized) { "Service not initialized" }

            val startTime = System.currentTimeMillis()

            try {
                // Step 1: Segment audio into speech regions
                val vadService = createVADService() // Get from service container
                val audioSegments = audioSegmentation.segmentAudio(
                    audioData = audioData,
                    vadService = vadService,
                    minimumSegmentDuration = configuration.minimumSegmentDuration
                )

                // Step 2: Extract voice embeddings for each segment
                val speechSegments = audioSegments.map { segment ->
                    val embedding = embeddingExtractor.extractVoiceEmbedding(
                        convertFloatToBytes(segment.audioData)
                    )

                    SpeechSegment(
                        startTime = segment.startTime,
                        endTime = segment.endTime,
                        speakerId = "", // Will be assigned during clustering
                        confidence = 0f, // Will be calculated during identification
                        audioData = convertFloatToBytes(segment.audioData),
                        voiceEmbedding = embedding
                    )
                }

                // Step 3: Identify speakers for each segment
                val identifiedSegments = identifySpeakersForSegments(speechSegments)

                // Step 4: Create speaker info list
                val speakerInfoList = createSpeakerInfoList(identifiedSegments)

                val endTime = System.currentTimeMillis()

                DiarizationResult(
                    segments = identifiedSegments,
                    speakers = speakerInfoList,
                    overallConfidence = calculateOverallConfidence(identifiedSegments),
                    processingTimeMs = endTime - startTime
                )

            } catch (e: Exception) {
                logger.error("Audio processing failed", e)
                throw e
            }
        }

    override suspend fun processAudioWithTranscription(
        audioData: ByteArray,
        transcription: String,
        timestamps: List<TimestampInfo>
    ): DiarizationResult = withContext(Dispatchers.IO) {
        // Process audio normally
        val diarizationResult = processAudio(audioData)

        // Align transcription with speaker segments
        val alignedSegments = alignTranscriptionWithSpeakers(
            diarizationResult.segments,
            timestamps
        )

        diarizationResult.copy(segments = alignedSegments)
    }

    override suspend fun createSpeakerProfile(
        speakerId: String,
        audioSamples: List<ByteArray>,
        name: String?
    ): SpeakerProfile = withContext(Dispatchers.IO) {
        require(audioSamples.isNotEmpty()) { "Audio samples cannot be empty" }

        // Extract embeddings from all samples
        val embeddings = audioSamples.map { sample ->
            embeddingExtractor.extractVoiceEmbedding(sample)
        }

        // Calculate voice characteristics from first sample
        val characteristics = extractVoiceCharacteristics(audioSamples.first())

        val profile = SpeakerProfile(
            speakerId = speakerId,
            name = name,
            voiceEmbeddings = embeddings,
            characteristics = characteristics,
            creationTime = System.currentTimeMillis(),
            updateTime = System.currentTimeMillis(),
            sampleCount = audioSamples.size,
            confidenceHistory = List(audioSamples.size) { 1.0f }
        )

        // Save profile
        speakerProfileRepository.saveSpeakerProfile(profile)

        logger.info("Created speaker profile for $speakerId with ${audioSamples.size} samples")
        profile
    }

    override suspend fun identifySpeaker(audioData: ByteArray): SpeakerIdentificationResult =
        withContext(Dispatchers.IO) {
            val embedding = embeddingExtractor.extractVoiceEmbedding(audioData)
            val knownSpeakers = speakerProfileRepository.getAllSpeakerProfiles()

            speakerClustering.identifySpeaker(
                voiceEmbedding = embedding,
                knownSpeakers = knownSpeakers,
                threshold = configuration.similarityThreshold
            )
        }

    override suspend fun extractVoiceEmbedding(audioData: ByteArray): FloatArray =
        withContext(Dispatchers.IO) {
            embeddingExtractor.extractVoiceEmbedding(audioData)
        }

    override fun calculateSimilarity(embedding1: FloatArray, embedding2: FloatArray): Float {
        return speakerClustering.calculateEmbeddingSimilarity(embedding1, embedding2)
    }

    override suspend fun getSpeakerProfiles(): List<SpeakerProfile> {
        return speakerProfileRepository.getAllSpeakerProfiles()
    }

    override suspend fun updateSpeakerProfile(speakerId: String, audioData: ByteArray): Boolean =
        withContext(Dispatchers.IO) {
            try {
                val existingProfile = speakerProfileRepository.getSpeakerProfile(speakerId)
                    ?: return@withContext false

                val newEmbedding = embeddingExtractor.extractVoiceEmbedding(audioData)

                val updatedProfile = existingProfile.copy(
                    voiceEmbeddings = existingProfile.voiceEmbeddings + newEmbedding,
                    updateTime = System.currentTimeMillis(),
                    sampleCount = existingProfile.sampleCount + 1
                )

                speakerProfileRepository.saveSpeakerProfile(updatedProfile)
                true
            } catch (e: Exception) {
                logger.error("Failed to update speaker profile: $speakerId", e)
                false
            }
        }

    override suspend fun deleteSpeakerProfile(speakerId: String): Boolean {
        return try {
            speakerProfileRepository.deleteSpeakerProfile(speakerId)
            true
        } catch (e: Exception) {
            logger.error("Failed to delete speaker profile: $speakerId", e)
            false
        }
    }

    override fun processAudioStream(audioStream: Flow<ByteArray>): Flow<SpeechSegment> = flow {
        val audioBuffer = mutableListOf<Byte>()
        val bufferDurationMs = 2000 // Process 2-second chunks
        val sampleRate = 16000
        val bytesPerSample = 2 // 16-bit
        val maxBufferSize = (bufferDurationMs * sampleRate * bytesPerSample) / 1000

        audioStream.collect { audioChunk ->
            audioBuffer.addAll(audioChunk.toList())

            if (audioBuffer.size >= maxBufferSize) {
                val processChunk = audioBuffer.take(maxBufferSize).toByteArray()
                audioBuffer.clear()
                audioBuffer.addAll(audioBuffer.drop(maxBufferSize))

                // Process chunk
                val result = processAudio(processChunk)
                result.segments.forEach { segment ->
                    emit(segment)
                }
            }
        }

        // Process remaining audio
        if (audioBuffer.isNotEmpty()) {
            val remainingChunk = audioBuffer.toByteArray()
            val result = processAudio(remainingChunk)
            result.segments.forEach { segment ->
                emit(segment)
            }
        }
    }.flowOn(Dispatchers.IO)

    override fun cleanup() {
        isInitialized = false
        logger.info("Speaker diarization service cleaned up")
    }

    override val isReady: Boolean get() = isInitialized
    override val supportedAudioFormats: List<String> = listOf("PCM_16BIT", "WAV")
    override val maxSupportedSpeakers: Int get() = configuration.maxSpeakers

    // Private helper methods
    private suspend fun identifySpeakersForSegments(
        segments: List<SpeechSegment>
    ): List<SpeechSegment> {
        val knownSpeakers = speakerProfileRepository.getAllSpeakerProfiles()

        return segments.map { segment ->
            val embedding = segment.voiceEmbedding
                ?: throw IllegalStateException("Segment missing voice embedding")

            val identification = speakerClustering.identifySpeaker(
                voiceEmbedding = embedding,
                knownSpeakers = knownSpeakers,
                threshold = configuration.similarityThreshold
            )

            // If new speaker and learning is enabled, create profile
            if (identification.isNewSpeaker && configuration.enableSpeakerLearning) {
                val audioData = segment.audioData
                    ?: throw IllegalStateException("Segment missing audio data")

                createSpeakerProfile(
                    speakerId = identification.speakerId,
                    audioSamples = listOf(audioData)
                )
            }

            segment.copy(
                speakerId = identification.speakerId,
                confidence = identification.confidence
            )
        }
    }

    private fun createSpeakerInfoList(segments: List<SpeechSegment>): List<SpeakerInfo> {
        return segments.groupBy { it.speakerId }.map { (speakerId, speakerSegments) ->
            val avgConfidence = speakerSegments.map { it.confidence }.average().toFloat()
            val totalDuration = speakerSegments.sumOf { it.endTime - it.startTime }
            val embedding = speakerSegments.first().voiceEmbedding
                ?: throw IllegalStateException("Missing voice embedding")

            SpeakerInfo(
                id = speakerId,
                confidence = avgConfidence,
                voiceEmbedding = embedding,
                totalSpeechDuration = totalDuration,
                averageConfidence = avgConfidence
            )
        }
    }

    private fun calculateOverallConfidence(segments: List<SpeechSegment>): Float {
        return if (segments.isEmpty()) 0f
        else segments.map { it.confidence }.average().toFloat()
    }
}
```

**Success Criteria**:
- [ ] Complete service implementation with all interface methods
- [ ] Real-time streaming audio processing works
- [ ] Speaker profile management functions correctly
- [ ] Integration with VAD and other components works
- [ ] Performance is acceptable for real-time use

---

## Phase 4: Integration and Testing (Day 10-12)
**Duration**: 2-3 days
**Priority**: MEDIUM

### Task 4.1: Android App Integration
**Files**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/`

```kotlin
// Update VoiceAssistantViewModel to include speaker diarization
class EnhancedVoiceAssistantViewModel(
    private val voicePipelineService: VoicePipelineService
) : ViewModel() {

    private val _speakerInfo = MutableStateFlow<List<SpeakerInfo>>(emptyList())
    val speakerInfo: StateFlow<List<SpeakerInfo>> = _speakerInfo.asStateFlow()

    fun enableSpeakerDiarization() {
        viewModelScope.launch {
            try {
                // Initialize speaker diarization component
                val config = SpeakerDiarizationConfiguration(
                    enableRealTimeProcessing = true,
                    maxSpeakers = 4,
                    similarityThreshold = 0.75f
                )

                val diarizationComponent = SpeakerDiarizationComponent(config)
                diarizationComponent.initialize()

                // Process voice input with speaker identification
                voicePipelineService.events
                    .filterIsInstance<VoicePipelineEvent.TranscriptionComplete>()
                    .collect { event ->
                        // Perform diarization on transcribed audio
                        val result = diarizationComponent.diarizeWithTranscription(event.audioData)

                        _speakerInfo.value = result.diarizationResult.speakers

                        // Update UI with speaker-labeled transcript
                        updateConversationWithSpeakers(result.labeledTranscript)
                    }

            } catch (e: Exception) {
                logger.error("Failed to enable speaker diarization", e)
            }
        }
    }

    private fun updateConversationWithSpeakers(labeledTranscript: List<LabeledTranscriptSegment>) {
        // Update conversation history with speaker labels
        val speakerMessages = labeledTranscript.groupBy { it.speakerId }.map { (speakerId, segments) ->
            val fullText = segments.joinToString(" ") { it.text }
            SpeakerMessage(speakerId, fullText, segments.first().startTime)
        }

        // Update UI state with speaker-labeled messages
        _uiState.value = _uiState.value.copy(
            speakerMessages = speakerMessages,
            showSpeakerLabels = true
        )
    }
}

data class SpeakerMessage(
    val speakerId: String,
    val message: String,
    val timestamp: Long
)
```

### Task 4.2: Provider Registration
**Files**: `modules/runanywhere-speaker-diarization/src/commonMain/kotlin/SpeakerDiarizationModule.kt`

```kotlin
object SpeakerDiarizationModule {
    fun register() {
        ModuleRegistry.registerSpeakerDiarizationProvider(DefaultSpeakerDiarizationProvider())
        logger.info("Speaker diarization provider registered successfully")
    }
}

class DefaultSpeakerDiarizationProvider : SpeakerDiarizationServiceProvider {
    override suspend fun createSpeakerDiarizationService(
        configuration: SpeakerDiarizationConfiguration
    ): SpeakerDiarizationService {
        val service = DefaultSpeakerDiarizationService(configuration)

        if (!service.initialize()) {
            throw SDKError.ComponentInitializationFailed("Failed to initialize speaker diarization service")
        }

        return service
    }

    override fun canHandle(configuration: Any?): Boolean = true
    override val name: String = "Default Speaker Diarization Provider"
}
```

**Success Criteria**:
- [ ] Speaker diarization integrates with Android voice assistant
- [ ] Speaker labels appear in conversation UI
- [ ] Speaker profiles are created and managed
- [ ] Multi-speaker conversations work correctly
- [ ] Provider registration works automatically

---

## Risk Assessment & Mitigation

### 🔴 Critical Risks
1. **Algorithm Complexity**: Speaker identification algorithms are complex
   - **Mitigation**: Start with simple similarity-based approach, iterate
   - **Fallback**: Use cloud-based speaker diarization service

2. **Performance Impact**: Real-time processing may be CPU intensive
   - **Mitigation**: Optimize algorithms, use background processing
   - **Monitoring**: Add performance metrics and memory usage tracking

3. **Accuracy Requirements**: Speaker identification needs to be reasonably accurate
   - **Mitigation**: Extensive testing with different speakers and conditions
   - **Tuning**: Adjustable similarity thresholds and confidence levels

### 🟡 Medium Risks
1. **Memory Usage**: Voice embeddings and profiles consume memory
   - **Mitigation**: Implement profile cleanup and memory management
   - **Optimization**: Use smaller embedding sizes where possible

2. **Storage Requirements**: Speaker profiles need persistent storage
   - **Mitigation**: Implement efficient storage with compression
   - **Privacy**: Ensure profiles can be deleted per user request

---

## Success Metrics

### 🎯 Functional Metrics
- [ ] Speaker identification accuracy > 80% for known speakers
- [ ] New speaker detection works reliably
- [ ] Multi-speaker conversation transcription with labels
- [ ] Speaker profile creation and management works
- [ ] Real-time processing with acceptable latency

### 📊 Performance Metrics
- **Processing Latency**: < 2 seconds for 10-second audio clips
- **Memory Usage**: < 100MB for speaker profiles and processing
- **Accuracy**: > 80% speaker identification accuracy
- **Real-time Factor**: Process audio faster than real-time

### 🔗 Integration Metrics
- [ ] Android app shows speaker-labeled conversations
- [ ] SDK component integrates with STT pipeline
- [ ] Provider registration works automatically
- [ ] Voice assistant supports multi-speaker scenarios

---

## Post-Implementation Priority

### Immediate Impact
- **Closes Critical Feature Gap**: Brings Kotlin SDK to feature parity with iOS
- **Enables Advanced Voice Features**: Multi-speaker conversation support
- **Competitive Advantage**: Restores missing core capability

### Future Enhancements
1. **ML Model Integration**: Use pre-trained speaker embedding models
2. **Cloud Fallback**: Integrate with cloud speaker diarization services
3. **Speaker Recognition**: Named speaker identification
4. **Voice Cloning Detection**: Security features for voice authentication

This emergency speaker diarization implementation plan addresses the critical missing feature and brings the Kotlin SDK to functional parity with the iOS implementation.
