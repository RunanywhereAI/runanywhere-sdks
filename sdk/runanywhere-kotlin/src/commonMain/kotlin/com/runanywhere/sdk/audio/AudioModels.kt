package com.runanywhere.sdk.audio

import kotlinx.serialization.Serializable

/**
 * Voice audio chunk data structure (matching iOS implementation)
 * This represents a chunk of audio data captured from the microphone
 */
data class VoiceAudioChunk(
    val samples: FloatArray,
    val timestamp: Double,
    val sampleRate: Int,
    val channels: Int,
    val sequenceNumber: Int,
    val isFinal: Boolean
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as VoiceAudioChunk

        if (!samples.contentEquals(other.samples)) return false
        if (timestamp != other.timestamp) return false
        if (sampleRate != other.sampleRate) return false
        if (channels != other.channels) return false
        if (sequenceNumber != other.sequenceNumber) return false
        if (isFinal != other.isFinal) return false

        return true
    }

    override fun hashCode(): Int {
        var result = samples.contentHashCode()
        result = 31 * result + timestamp.hashCode()
        result = 31 * result + sampleRate
        result = 31 * result + channels
        result = 31 * result + sequenceNumber
        result = 31 * result + isFinal.hashCode()
        return result
    }
}

/**
 * Audio capture exception
 * Used for audio-related errors across all platforms
 */
class AudioCaptureException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)

/**
 * Audio capture options for configuring microphone capture
 * Matches iOS AudioCapture configuration pattern
 */
@Serializable
data class AudioCaptureOptions(
    /** Sample rate in Hz (default: 16000 for Whisper compatibility) */
    val sampleRate: Int = 16000,

    /** Number of channels: 1 for mono, 2 for stereo (default: 1) */
    val channels: Int = 1,

    /** Audio format/encoding (default: PCM 16-bit) */
    val audioFormat: AudioEncoding = AudioEncoding.PCM_16BIT,

    /** Buffer size multiplier (default: 2) */
    val bufferSizeMultiplier: Int = 2,

    /** Minimum buffer size in samples (default: 1600 = 100ms at 16kHz) */
    val minBufferSize: Int = 1600,

    /** Enable echo cancellation (platform-dependent) */
    val echoCancellation: Boolean = false,

    /** Enable noise suppression (platform-dependent) */
    val noiseSuppression: Boolean = false,

    /** Enable automatic gain control (platform-dependent) */
    val autoGainControl: Boolean = false,

    /** Audio source type (microphone, voice communication, etc.) */
    val audioSource: AudioSource = AudioSource.DEFAULT
) {
    companion object {
        /**
         * Default options for general audio capture
         */
        val DEFAULT = AudioCaptureOptions()

        /**
         * Optimized for speech recognition (Whisper, STT)
         */
        val SPEECH_RECOGNITION = AudioCaptureOptions(
            sampleRate = 16000,
            channels = 1,
            audioFormat = AudioEncoding.PCM_16BIT,
            noiseSuppression = true,
            audioSource = AudioSource.VOICE_RECOGNITION
        )

        /**
         * Optimized for voice communication
         */
        val VOICE_COMMUNICATION = AudioCaptureOptions(
            sampleRate = 16000,
            channels = 1,
            audioFormat = AudioEncoding.PCM_16BIT,
            echoCancellation = true,
            noiseSuppression = true,
            autoGainControl = true,
            audioSource = AudioSource.VOICE_COMMUNICATION
        )

        /**
         * High quality audio capture
         */
        val HIGH_QUALITY = AudioCaptureOptions(
            sampleRate = 44100,
            channels = 2,
            audioFormat = AudioEncoding.PCM_16BIT,
            bufferSizeMultiplier = 4
        )
    }

    fun validate() {
        require(sampleRate > 0) { "Sample rate must be positive" }
        require(channels in 1..2) { "Channels must be 1 (mono) or 2 (stereo)" }
        require(bufferSizeMultiplier > 0) { "Buffer size multiplier must be positive" }
        require(minBufferSize > 0) { "Minimum buffer size must be positive" }
    }
}

/**
 * Audio encoding formats
 */
@Serializable
enum class AudioEncoding {
    PCM_8BIT,
    PCM_16BIT,
    PCM_FLOAT
}

/**
 * Audio source types
 * Mapped to platform-specific audio sources
 */
@Serializable
enum class AudioSource {
    /** Default microphone */
    DEFAULT,

    /** Microphone audio source */
    MIC,

    /** Optimized for voice recognition */
    VOICE_RECOGNITION,

    /** Optimized for voice communication (VoIP) */
    VOICE_COMMUNICATION,

    /** Camcorder audio source */
    CAMCORDER,

    /** Unprocessed audio source (if available) */
    UNPROCESSED
}

/**
 * Audio capture statistics
 */
@Serializable
data class AudioCaptureStats(
    val totalChunks: Long = 0,
    val totalSamples: Long = 0,
    val totalBytes: Long = 0,
    val averageRMS: Float = 0f,
    val peakRMS: Float = 0f,
    val droppedChunks: Long = 0,
    val recordingDuration: Double = 0.0
)
