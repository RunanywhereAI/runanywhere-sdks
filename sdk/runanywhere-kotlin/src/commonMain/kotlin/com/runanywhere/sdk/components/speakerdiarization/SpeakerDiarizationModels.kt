package com.runanywhere.sdk.components.speakerdiarization

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.components.stt.STTOutput
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow

// MARK: - Speaker Diarization Configuration

/**
 * Configuration for Speaker Diarization component (matches iOS SpeakerDiarizationConfiguration)
 */
data class SpeakerDiarizationConfiguration(
    // Component type
    override val componentType: SDKComponent = SDKComponent.SPEAKER_DIARIZATION,

    // Model ID
    override val modelId: String? = null,

    // Speaker detection parameters
    val maxSpeakers: Int = 10,
    val minSpeechDuration: Double = 0.5, // seconds
    val speakerChangeThreshold: Float = 0.7f, // cosine similarity threshold
    val windowSize: Double = 2.0, // seconds
    val stepSize: Double = 0.5, // seconds

    // Audio processing parameters
    val sampleRate: Int = 16000,
    val embeddingSize: Int = 128,

    // Energy-based detection settings
    val energyThreshold: Float = 0.01f,
    val silenceThreshold: Float = 0.005f,

    // Performance optimization
    val useGPUIfAvailable: Boolean = true,
    val enableRealTimeProcessing: Boolean = true,
    val batchProcessingMode: Boolean = false
) : ComponentConfiguration, ComponentInitParameters {

    override fun validate() {
        if (maxSpeakers <= 0 || maxSpeakers > 50) {
            throw SDKError.ValidationFailed("Max speakers must be between 1 and 50")
        }
        if (minSpeechDuration <= 0.0 || minSpeechDuration > 10.0) {
            throw SDKError.ValidationFailed("Min speech duration must be between 0.1 and 10.0 seconds")
        }
        if (speakerChangeThreshold < 0.0f || speakerChangeThreshold > 1.0f) {
            throw SDKError.ValidationFailed("Speaker change threshold must be between 0.0 and 1.0")
        }
        if (windowSize <= 0.0 || windowSize > 30.0) {
            throw SDKError.ValidationFailed("Window size must be between 0.1 and 30.0 seconds")
        }
        if (stepSize <= 0.0 || stepSize > windowSize) {
            throw SDKError.ValidationFailed("Step size must be between 0.1 seconds and window size")
        }
        if (sampleRate <= 0 || sampleRate > 48000) {
            throw SDKError.ValidationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        if (embeddingSize <= 0 || embeddingSize > 512) {
            throw SDKError.ValidationFailed("Embedding size must be between 1 and 512")
        }
    }
}

// MARK: - Speaker Data Models

/**
 * Speaker information (matches iOS SpeakerInfo)
 */
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float? = null,
    val embedding: FloatArray? = null,
    val createdAt: Long = getCurrentTimeMillis()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerInfo) return false

        return id == other.id &&
                name == other.name &&
                confidence == other.confidence &&
                embedding?.contentEquals(other.embedding ?: FloatArray(0)) ?: (other.embedding == null) &&
                createdAt == other.createdAt
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + (name?.hashCode() ?: 0)
        result = 31 * result + (confidence?.hashCode() ?: 0)
        result = 31 * result + (embedding?.contentHashCode() ?: 0)
        result = 31 * result + createdAt.hashCode()
        return result
    }
}

/**
 * Speaker profile with aggregate statistics (matches iOS SpeakerProfile)
 */
data class SpeakerProfile(
    val id: String,
    val embedding: FloatArray? = null,
    val totalSpeakingTime: Double = 0.0, // seconds
    val segmentCount: Int = 0,
    val name: String? = null,
    val averageConfidence: Float = 0.0f,
    val lastUpdated: Long = getCurrentTimeMillis()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerProfile) return false

        return id == other.id &&
                embedding?.contentEquals(other.embedding ?: FloatArray(0)) ?: (other.embedding == null) &&
                totalSpeakingTime == other.totalSpeakingTime &&
                segmentCount == other.segmentCount &&
                name == other.name &&
                averageConfidence == other.averageConfidence &&
                lastUpdated == other.lastUpdated
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + (embedding?.contentHashCode() ?: 0)
        result = 31 * result + totalSpeakingTime.hashCode()
        result = 31 * result + segmentCount
        result = 31 * result + (name?.hashCode() ?: 0)
        result = 31 * result + averageConfidence.hashCode()
        result = 31 * result + lastUpdated.hashCode()
        return result
    }
}

/**
 * Speaker segment with temporal information (matches iOS SpeakerSegment)
 */
data class SpeakerSegment(
    val speakerId: String,
    val startTime: Double, // seconds
    val endTime: Double, // seconds
    val confidence: Float,
    val energy: Float = 0.0f,
    val speechDuration: Double = endTime - startTime
) {
    init {
        require(endTime >= startTime) { "End time must be >= start time" }
        require(confidence >= 0.0f && confidence <= 1.0f) { "Confidence must be between 0.0 and 1.0" }
    }
}

/**
 * Labeled transcription with speaker attribution (matches iOS LabeledTranscription)
 */
data class LabeledTranscription(
    val segments: List<LabeledSegment>,
    val speakers: List<SpeakerProfile>,
    val totalDuration: Double = segments.maxOfOrNull { it.endTime } ?: 0.0
) {
    /**
     * Labeled segment with speaker ID and text (matches iOS LabeledSegment)
     */
    data class LabeledSegment(
        val speakerId: String,
        val text: String,
        val startTime: Double, // seconds
        val endTime: Double, // seconds
        val confidence: Float = 1.0f
    ) {
        init {
            require(endTime >= startTime) { "End time must be >= start time" }
            require(confidence >= 0.0f && confidence <= 1.0f) { "Confidence must be between 0.0 and 1.0" }
        }
    }

    /**
     * Format transcription for display with speaker labels
     */
    val formattedTranscript: String
        get() = segments.joinToString("\n") { segment ->
            val speakerName = speakers.find { it.id == segment.speakerId }?.name ?: segment.speakerId
            "[$speakerName]: ${segment.text}"
        }
}

/**
 * Diarization metadata (matches iOS DiarizationMetadata)
 */
data class DiarizationMetadata(
    val processingTime: Double, // seconds
    val audioLength: Double, // seconds
    val speakerCount: Int,
    val method: String, // "energy", "ml", "hybrid"
    val realTimeFactor: Double = if (audioLength > 0) processingTime / audioLength else 0.0,
    val averageConfidence: Float = 0.0f,
    val segmentCount: Int = 0
)

// MARK: - Input/Output Models

/**
 * Input for Speaker Diarization (matches iOS SpeakerDiarizationInput)
 */
data class SpeakerDiarizationInput(
    // Audio data to process
    val audioData: ByteArray = byteArrayOf(),

    // Audio buffer (alternative to data)
    val audioBuffer: FloatArray? = null,

    // Sample rate of audio
    val sampleRate: Int = 16000,

    // Optional transcription for labeling
    val transcription: STTOutput? = null,

    // Processing options
    val options: SpeakerDiarizationOptions? = null
) : ComponentInput {

    override fun validate() {
        if (audioData.isEmpty() && audioBuffer == null) {
            throw SDKError.ValidationFailed("SpeakerDiarizationInput must contain either audioData or audioBuffer")
        }
        if (sampleRate <= 0 || sampleRate > 48000) {
            throw SDKError.ValidationFailed("Sample rate must be between 1 and 48000 Hz")
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeakerDiarizationInput) return false

        return audioData.contentEquals(other.audioData) &&
                audioBuffer?.contentEquals(other.audioBuffer ?: FloatArray(0)) ?: (other.audioBuffer == null) &&
                sampleRate == other.sampleRate &&
                transcription == other.transcription &&
                options == other.options
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + (audioBuffer?.contentHashCode() ?: 0)
        result = 31 * result + sampleRate
        result = 31 * result + (transcription?.hashCode() ?: 0)
        result = 31 * result + (options?.hashCode() ?: 0)
        return result
    }
}

/**
 * Output from Speaker Diarization (matches iOS SpeakerDiarizationOutput)
 */
data class SpeakerDiarizationOutput(
    // Temporal segments with speaker assignments
    val segments: List<SpeakerSegment>,

    // Speaker profiles with statistics
    val speakers: List<SpeakerProfile>,

    // Labeled transcription if input transcription provided
    val labeledTranscription: LabeledTranscription? = null,

    // Processing metadata
    val metadata: DiarizationMetadata,

    // Timestamp (required by ComponentOutput)
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput

/**
 * Options for speaker diarization processing
 */
data class SpeakerDiarizationOptions(
    val maxSpeakers: Int? = null,
    val minSpeechDuration: Double? = null,
    val speakerChangeThreshold: Float? = null,
    val enableLabeling: Boolean = true,
    val preserveSpeakerHistory: Boolean = true
)

// MARK: - Speaker Diarization Results

/**
 * Result from speaker diarization service
 */
data class SpeakerDiarizationResult(
    val speakers: List<SpeakerInfo>,
    val segments: List<SpeakerSegment>,
    val processingTime: Double,
    val confidence: Float
)

// MARK: - Speaker Detection Events

/**
 * Events emitted during speaker diarization
 */
sealed class SpeakerDiarizationEvent {
    object ProcessingStarted : SpeakerDiarizationEvent()
    object ProcessingCompleted : SpeakerDiarizationEvent()
    data class SpeakerDetected(val speaker: SpeakerInfo) : SpeakerDiarizationEvent()
    data class SpeakerChanged(val previous: SpeakerInfo?, val current: SpeakerInfo) : SpeakerDiarizationEvent()
    data class SegmentCompleted(val segment: SpeakerSegment) : SpeakerDiarizationEvent()
    data class Error(val error: SpeakerDiarizationError) : SpeakerDiarizationEvent()
}

// MARK: - Speaker Diarization Errors

sealed class SpeakerDiarizationError : Exception() {
    object ServiceNotInitialized : SpeakerDiarizationError()
    data class ProcessingFailed(override val cause: Throwable) : SpeakerDiarizationError()
    data class ModelNotFound(val modelId: String) : SpeakerDiarizationError()
    object AudioFormatNotSupported : SpeakerDiarizationError()
    object InsufficientAudioData : SpeakerDiarizationError()
    data class ConfigurationInvalid(val details: String) : SpeakerDiarizationError()
    object TooManyActiveSpeakers : SpeakerDiarizationError()

    override val message: String
        get() = when (this) {
            is ServiceNotInitialized -> "Speaker diarization service is not initialized"
            is ProcessingFailed -> "Speaker diarization processing failed: ${cause.localizedMessage}"
            is ModelNotFound -> "Speaker diarization model not found: $modelId"
            is AudioFormatNotSupported -> "Audio format is not supported for speaker diarization"
            is InsufficientAudioData -> "Insufficient audio data for speaker diarization"
            is ConfigurationInvalid -> "Speaker diarization configuration is invalid: $details"
            is TooManyActiveSpeakers -> "Too many active speakers detected (exceeds maximum limit)"
        }
}

// MARK: - Audio Processing Data Classes

/**
 * Audio chunk for processing
 */
data class AudioChunk(
    val samples: FloatArray,
    val startTime: Double,
    val endTime: Double,
    val sampleRate: Int
) {
    val duration: Double = endTime - startTime

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AudioChunk) return false

        return samples.contentEquals(other.samples) &&
                startTime == other.startTime &&
                endTime == other.endTime &&
                sampleRate == other.sampleRate
    }

    override fun hashCode(): Int {
        var result = samples.contentHashCode()
        result = 31 * result + startTime.hashCode()
        result = 31 * result + endTime.hashCode()
        result = 31 * result + sampleRate
        return result
    }
}

/**
 * Audio feature extraction result
 */
data class AudioFeatures(
    val rmsEnergy: Float,
    val zeroCrossingRate: Float,
    val spectralCentroid: Float,
    val embedding: FloatArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AudioFeatures) return false

        return rmsEnergy == other.rmsEnergy &&
                zeroCrossingRate == other.zeroCrossingRate &&
                spectralCentroid == other.spectralCentroid &&
                embedding.contentEquals(other.embedding)
    }

    override fun hashCode(): Int {
        var result = rmsEnergy.hashCode()
        result = 31 * result + zeroCrossingRate.hashCode()
        result = 31 * result + spectralCentroid.hashCode()
        result = 31 * result + embedding.contentHashCode()
        return result
    }
}
