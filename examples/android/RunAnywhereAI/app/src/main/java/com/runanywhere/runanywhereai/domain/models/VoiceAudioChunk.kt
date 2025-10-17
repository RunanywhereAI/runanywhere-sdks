package com.runanywhere.runanywhereai.domain.models

/**
 * Represents a chunk of audio data for voice processing
 * TODO: This will be used by the SDK's enhanced voice pipeline
 */
data class VoiceAudioChunk(
    val data: FloatArray,
    val sampleRate: Int,
    val timestamp: Long,
    val channels: Int = 1
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as VoiceAudioChunk
        return data.contentEquals(other.data) &&
               sampleRate == other.sampleRate &&
               timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + sampleRate
        result = 31 * result + timestamp.hashCode()
        return result
    }
}
