package com.runanywhere.sdk.voice.models

import kotlinx.serialization.Serializable

/**
 * Voice Activity Detection Models
 * One-to-one mapping from iOS VADModels.swift
 */

/**
 * Input data for VAD processing
 */
@Serializable
data class VADInput(
    val audioSamples: FloatArray,
    val sampleRate: Int = 16000,
    val frameSize: Int = 512,
    val metadata: VADMetadata? = null
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as VADInput
        return audioSamples.contentEquals(other.audioSamples) &&
                sampleRate == other.sampleRate &&
                frameSize == other.frameSize &&
                metadata == other.metadata
    }

    override fun hashCode(): Int {
        var result = audioSamples.contentHashCode()
        result = 31 * result + sampleRate
        result = 31 * result + frameSize
        result = 31 * result + (metadata?.hashCode() ?: 0)
        return result
    }
}

/**
 * Output from VAD processing
 */
@Serializable
data class VADOutput(
    val isSpeech: Boolean,
    val speechProbability: Float,
    val energy: Float = 0.0f,
    val zeroCrossingRate: Float = 0.0f,
    val segments: List<SpeechSegment> = emptyList(),
    val metadata: Map<String, String> = emptyMap()
)

/**
 * VAD configuration parameters
 */
@Serializable
data class VADConfiguration(
    val algorithm: VADAlgorithm = VADAlgorithm.ENERGY_BASED,
    val energyThreshold: Float = 50.0f,
    val silenceThreshold: Float = 30.0f,
    val minSpeechDuration: Long = 200L, // milliseconds
    val minSilenceDuration: Long = 300L, // milliseconds
    val preSpeechPadding: Long = 100L, // milliseconds
    val postSpeechPadding: Long = 100L, // milliseconds
    val maxSpeechDuration: Long? = null, // milliseconds
    val sampleRate: Int = 16000,
    val frameSize: Int = 512,
    val frameStep: Int = 160,
    val enableNoiseReduction: Boolean = false,
    val enableAdaptiveThreshold: Boolean = true,
    val smoothingWindow: Int = 5
)

/**
 * Speech segment with timing information
 */
@Serializable
data class SpeechSegment(
    val startTime: Long,
    val endTime: Long,
    val duration: Long = endTime - startTime,
    val confidence: Float = 0.0f,
    val averageEnergy: Float = 0.0f,
    val peakEnergy: Float = 0.0f,
    val isFinal: Boolean = false
)

/**
 * VAD Algorithm types
 */
@Serializable
enum class VADAlgorithm {
    ENERGY_BASED,
    WEBRTC_VAD,
    SILERO_VAD,
    ML_BASED,
    HYBRID;

    val displayName: String
        get() = when (this) {
            ENERGY_BASED -> "Energy-based VAD"
            WEBRTC_VAD -> "WebRTC VAD"
            SILERO_VAD -> "Silero VAD"
            ML_BASED -> "ML-based VAD"
            HYBRID -> "Hybrid VAD"
        }

    val requiresModel: Boolean
        get() = when (this) {
            SILERO_VAD, ML_BASED -> true
            else -> false
        }
}

/**
 * VAD processing state
 */
@Serializable
enum class VADState {
    IDLE,
    INITIALIZING,
    READY,
    DETECTING,
    SPEECH_DETECTED,
    SILENCE_DETECTED,
    ERROR;

    val isActive: Boolean
        get() = this in listOf(DETECTING, SPEECH_DETECTED)

    val canProcess: Boolean
        get() = this in listOf(READY, DETECTING, SPEECH_DETECTED, SILENCE_DETECTED)
}

/**
 * VAD Result with confidence
 */
@Serializable
data class VADResult(
    val isSpeech: Boolean,
    val confidence: Float,
    val timestamp: Long = System.currentTimeMillis(),
    val frameEnergy: Float = 0.0f,
    val adaptiveThreshold: Float? = null
)

/**
 * VAD Metadata for processing context
 */
@Serializable
data class VADMetadata(
    val sessionId: String? = null,
    val userId: String? = null,
    val deviceInfo: String? = null,
    val environmentNoise: Float? = null,
    val previousSegments: Int = 0
)

/**
 * VAD Statistics for monitoring
 */
@Serializable
data class VADStatistics(
    val totalFrames: Long = 0,
    val speechFrames: Long = 0,
    val silenceFrames: Long = 0,
    val totalSegments: Int = 0,
    val averageSegmentDuration: Float = 0.0f,
    val averageConfidence: Float = 0.0f,
    val processingTimeMs: Long = 0,
    val lastUpdateTime: Long = System.currentTimeMillis()
) {
    val speechRatio: Float
        get() = if (totalFrames > 0) speechFrames.toFloat() / totalFrames else 0.0f

    val silenceRatio: Float
        get() = if (totalFrames > 0) silenceFrames.toFloat() / totalFrames else 0.0f
}

/**
 * VAD Model configuration
 */
@Serializable
data class VADModelConfig(
    val modelPath: String? = null,
    val modelType: VADModelType = VADModelType.ENERGY,
    val modelVersion: String? = null,
    val useGPU: Boolean = false,
    val threads: Int = 1
)

/**
 * VAD Model types
 */
@Serializable
enum class VADModelType {
    ENERGY,
    WEBRTC,
    SILERO,
    ONNX,
    CUSTOM;

    val displayName: String
        get() = when (this) {
            ENERGY -> "Energy-based"
            WEBRTC -> "WebRTC"
            SILERO -> "Silero"
            ONNX -> "ONNX"
            CUSTOM -> "Custom"
        }
}

/**
 * Audio level information
 */
@Serializable
data class AudioLevel(
    val peak: Float,
    val rms: Float,
    val db: Float,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * VAD Error types
 */
@Serializable
sealed class VADError : Exception() {
    data class InitializationError(override val message: String) : VADError()
    data class ProcessingError(override val message: String) : VADError()
    data class ModelNotFound(override val message: String) : VADError()
    data class InvalidConfiguration(override val message: String) : VADError()
    data class AudioFormatError(override val message: String) : VADError()
}
