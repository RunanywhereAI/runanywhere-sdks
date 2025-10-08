package com.runanywhere.sdk.audio

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