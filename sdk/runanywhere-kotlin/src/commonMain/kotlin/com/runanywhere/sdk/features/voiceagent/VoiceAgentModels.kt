package com.runanywhere.sdk.features.voiceagent

import com.runanywhere.sdk.core.capabilities.ComponentOutput
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

// MARK: - Voice Audio Chunk

/**
 * A chunk of audio data for streaming processing
 * Matches iOS VoiceAudioChunk exactly
 */
data class VoiceAudioChunk(
    /** The audio samples as Float array (simplified - no Data conversion needed) */
    val samples: FloatArray,
    /** Timestamp when this chunk was captured */
    val timestamp: Double,
    /** Sample rate of the audio (e.g., 16000 for 16kHz) */
    val sampleRate: Int = 16000,
    /** Number of channels (1 for mono, 2 for stereo) */
    val channels: Int = 1,
    /** Sequence number for ordering chunks */
    val sequenceNumber: Int = 0,
    /** Whether this is the final chunk in a stream */
    val isFinal: Boolean = false,
) {
    /**
     * Convert Float samples to ByteArray (4 bytes per float, little-endian)
     */
    val data: ByteArray
        get() {
            val bytes = ByteArray(samples.size * 4)
            for (i in samples.indices) {
                val bits = samples[i].toRawBits()
                bytes[i * 4] = (bits and 0xFF).toByte()
                bytes[i * 4 + 1] = ((bits shr 8) and 0xFF).toByte()
                bytes[i * 4 + 2] = ((bits shr 16) and 0xFF).toByte()
                bytes[i * 4 + 3] = ((bits shr 24) and 0xFF).toByte()
            }
            return bytes
        }

    /** Duration of this audio chunk in seconds */
    val duration: Double
        get() = samples.size.toDouble() / (sampleRate * channels).toDouble()

    /** Number of samples in this chunk */
    val sampleCount: Int
        get() = samples.size / channels

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VoiceAudioChunk) return false

        return samples.contentEquals(other.samples) &&
            timestamp == other.timestamp &&
            sampleRate == other.sampleRate &&
            channels == other.channels &&
            sequenceNumber == other.sequenceNumber &&
            isFinal == other.isFinal
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

// MARK: - VoiceAgent Configuration

/**
 * Configuration for VoiceAgent - aggregates all sub-component configurations
 * Matches iOS VoiceAgentConfiguration exactly
 */
data class VoiceAgentConfiguration(
    /** VAD configuration */
    val vadConfig: VADConfiguration = VADConfiguration(),
    /** STT configuration */
    val sttConfig: STTConfiguration = STTConfiguration(),
    /** LLM configuration */
    val llmConfig: LLMConfiguration = LLMConfiguration(),
    /** TTS configuration */
    val ttsConfig: TTSConfiguration = TTSConfiguration(),
) {
    /** Validate all configurations */
    fun validate() {
        vadConfig.validate()
        sttConfig.validate()
        llmConfig.validate()
        ttsConfig.validate()
    }
}

// MARK: - VoiceAgent Result

/**
 * Result from processing audio through the VoiceAgent pipeline
 * Matches iOS VoiceAgentResult structure exactly
 */
@Serializable
data class VoiceAgentResult(
    /** Whether speech was detected by VAD */
    val speechDetected: Boolean = false,
    /** Transcription from STT (null if no speech or STT not run) */
    val transcription: String? = null,
    /** LLM response text (null if transcription empty or LLM not run) */
    val response: String? = null,
    /** Synthesized audio from TTS (null if no response or TTS not run) */
    val synthesizedAudio: ByteArray? = null,
    /** Processing timestamp */
    override val timestamp: Long = getCurrentTimeMillis(),
) : ComponentOutput {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as VoiceAgentResult

        if (speechDetected != other.speechDetected) return false
        if (transcription != other.transcription) return false
        if (response != other.response) return false
        if (synthesizedAudio != null) {
            if (other.synthesizedAudio == null) return false
            if (!synthesizedAudio.contentEquals(other.synthesizedAudio)) return false
        } else if (other.synthesizedAudio != null) {
            return false
        }
        if (timestamp != other.timestamp) return false

        return true
    }

    override fun hashCode(): Int {
        var result = speechDetected.hashCode()
        result = 31 * result + (transcription?.hashCode() ?: 0)
        result = 31 * result + (response?.hashCode() ?: 0)
        result = 31 * result + (synthesizedAudio?.contentHashCode() ?: 0)
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

// MARK: - VoiceAgent Events (for streaming)

/**
 * Events emitted during streaming VoiceAgent processing
 * Matches iOS VoiceAgentEvent enum exactly
 */
sealed class VoiceAgentEvent {
    /** Full pipeline result */
    data class Processed(
        val result: VoiceAgentResult,
    ) : VoiceAgentEvent()

    /** VAD detection result */
    data class VadTriggered(
        val speechDetected: Boolean,
    ) : VoiceAgentEvent()

    /** STT transcription available */
    data class TranscriptionAvailable(
        val text: String,
    ) : VoiceAgentEvent()

    /** LLM response generated */
    data class ResponseGenerated(
        val text: String,
    ) : VoiceAgentEvent()

    /** TTS audio synthesized */
    data class AudioSynthesized(
        val data: ByteArray,
    ) : VoiceAgentEvent() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is AudioSynthesized) return false
            return data.contentEquals(other.data)
        }

        override fun hashCode(): Int = data.contentHashCode()
    }

    /** Pipeline error */
    data class Error(
        val error: Throwable,
    ) : VoiceAgentEvent()
}

// MARK: - VoiceAgent Service

/**
 * Simple service wrapper for VoiceAgent
 * VoiceAgent doesn't need an external service - it orchestrates other components
 * Matches iOS VoiceAgentService
 */
class VoiceAgentService {
    // No-op service - VoiceAgent orchestrates other component services
}

// MARK: - VoiceAgent Errors

/**
 * Errors specific to VoiceAgent processing
 */
sealed class VoiceAgentError : Exception() {
    /** Pipeline not initialized */
    object PipelineNotInitialized : VoiceAgentError() {
        @Suppress("UnusedPrivateMember")
        private fun readResolve(): Any = PipelineNotInitialized

        override val message: String = "VoiceAgent pipeline is not initialized"
    }

    /** Empty transcription - no speech detected */
    object EmptyTranscription : VoiceAgentError() {
        @Suppress("UnusedPrivateMember")
        private fun readResolve(): Any = EmptyTranscription

        override val message: String = "No speech detected in audio"
    }

    /** Pipeline was interrupted */
    data class PipelineInterrupted(
        val reason: String,
    ) : VoiceAgentError() {
        override val message: String = "Voice pipeline interrupted: $reason"
    }

    /** VAD component failed */
    data class VADFailed(
        val error: Throwable,
    ) : VoiceAgentError() {
        override val message: String = "VAD processing failed: ${error.message}"
        override val cause: Throwable = error
    }

    /** STT component failed */
    data class STTFailed(
        val error: Throwable,
    ) : VoiceAgentError() {
        override val message: String = "STT transcription failed: ${error.message}"
        override val cause: Throwable = error
    }

    /** LLM component failed */
    data class LLMFailed(
        val error: Throwable,
    ) : VoiceAgentError() {
        override val message: String = "LLM generation failed: ${error.message}"
        override val cause: Throwable = error
    }

    /** TTS component failed */
    data class TTSFailed(
        val error: Throwable,
    ) : VoiceAgentError() {
        override val message: String = "TTS synthesis failed: ${error.message}"
        override val cause: Throwable = error
    }

    /** Sub-component initialization failed */
    data class ComponentInitializationFailed(
        val component: String,
        val error: Throwable,
    ) : VoiceAgentError() {
        override val message: String = "$component initialization failed: ${error.message}"
        override val cause: Throwable = error
    }
}

// MARK: - Pipeline State

/**
 * Tracks the current state of the VoiceAgent pipeline
 */
enum class VoiceAgentPipelineState {
    IDLE,
    VAD_PROCESSING,
    STT_PROCESSING,
    LLM_PROCESSING,
    TTS_PROCESSING,
    COMPLETED,
    ERROR,
}
