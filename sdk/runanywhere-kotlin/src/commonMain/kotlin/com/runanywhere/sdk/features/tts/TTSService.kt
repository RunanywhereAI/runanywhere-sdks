package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.core.AudioFormat
import kotlinx.coroutines.flow.Flow

/**
 * Protocol for text-to-speech services.
 * Matches iOS TTSService protocol exactly.
 */
interface TTSService {
    /**
     * The inference framework used by this service.
     * Required for analytics and performance tracking.
     */
    val inferenceFramework: String

    /**
     * Initialize the TTS service
     */
    suspend fun initialize()

    /**
     * Synthesize text to audio
     * @param text The text to synthesize
     * @param options Synthesis options
     * @return Audio data
     */
    suspend fun synthesize(text: String, options: TTSOptions): ByteArray

    /**
     * Stream synthesis for long text
     * @param text The text to synthesize
     * @param options Synthesis options
     * @return Flow of audio chunks
     */
    fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray>

    /**
     * Stop current synthesis
     */
    fun stop()

    /**
     * Check if currently synthesizing
     */
    val isSynthesizing: Boolean

    /**
     * Get available voices
     */
    val availableVoices: List<String>

    /**
     * Cleanup resources
     */
    suspend fun cleanup()
}

/**
 * Options for text-to-speech synthesis.
 * Matches iOS TTSOptions struct exactly.
 */
data class TTSOptions(
    /** Voice to use for synthesis (null uses default) */
    val voice: String? = null,

    /** Language for synthesis (BCP-47 format, e.g., "en-US") */
    val language: String = "en-US",

    /** Speech rate (0.0 to 2.0, 1.0 is normal) */
    val rate: Float = 1.0f,

    /** Speech pitch (0.0 to 2.0, 1.0 is normal) */
    val pitch: Float = 1.0f,

    /** Speech volume (0.0 to 1.0) */
    val volume: Float = 1.0f,

    /** Audio format for output */
    val audioFormat: AudioFormat = AudioFormat.PCM,

    /** Sample rate for output audio in Hz */
    val sampleRate: Int = 16000,

    /** Whether to use SSML markup */
    val useSSML: Boolean = false,
) {
    companion object {
        /** Default options */
        val default = TTSOptions()

        /** Create options from TTSConfiguration */
        fun from(configuration: TTSConfiguration): TTSOptions = TTSOptions(
            voice = configuration.modelId,
            language = configuration.language,
            rate = configuration.speakingRate,
            pitch = configuration.pitch,
            volume = configuration.volume,
            audioFormat = configuration.audioFormat,
            sampleRate = if (configuration.audioFormat == AudioFormat.PCM) 16000 else 44100,
            useSSML = configuration.enableSSML,
        )
    }
}

/**
 * Configuration for TTS capability.
 * Matches iOS TTSConfiguration struct.
 */
data class TTSConfiguration(
    /** Voice identifier to use */
    val modelId: String? = null,

    /** Language for synthesis (BCP-47 format) */
    val language: String = "en-US",

    /** Speaking rate (0.0 to 2.0, 1.0 is normal) */
    val speakingRate: Float = 1.0f,

    /** Pitch adjustment (0.0 to 2.0, 1.0 is normal) */
    val pitch: Float = 1.0f,

    /** Volume (0.0 to 1.0) */
    val volume: Float = 1.0f,

    /** Output audio format */
    val audioFormat: AudioFormat = AudioFormat.PCM,

    /** Enable SSML processing */
    val enableSSML: Boolean = false,

    /** Framework preference for TTS */
    val preferredFramework: String? = null,
) {
    /** Validate configuration */
    fun validate() {
        require(speakingRate in 0.0f..2.0f) { "Speaking rate must be between 0.0 and 2.0" }
        require(pitch in 0.0f..2.0f) { "Pitch must be between 0.0 and 2.0" }
        require(volume in 0.0f..1.0f) { "Volume must be between 0.0 and 1.0" }
    }

    companion object {
        /** Default configuration */
        val default = TTSConfiguration()
    }
}

/**
 * Voice information for TTS.
 * Represents an available voice for synthesis.
 */
data class TTSVoice(
    /** Unique voice identifier */
    val id: String,

    /** Human-readable voice name */
    val name: String,

    /** Language code (BCP-47 format) */
    val language: String = "en-US",

    /** Voice gender */
    val gender: TTSGender = TTSGender.NEUTRAL,

    /** Voice quality indicator */
    val quality: TTSVoiceQuality = TTSVoiceQuality.STANDARD,
) {
    companion object {
        /** Default fallback voice */
        val DEFAULT = TTSVoice(
            id = "default",
            name = "Default",
            language = "en-US",
            gender = TTSGender.NEUTRAL,
        )
    }
}

/**
 * Voice gender enumeration.
 */
enum class TTSGender {
    MALE,
    FEMALE,
    NEUTRAL,
}

/**
 * Voice quality enumeration.
 */
enum class TTSVoiceQuality {
    /** Standard quality, faster synthesis */
    STANDARD,
    /** High quality, better audio */
    HIGH,
    /** Premium quality, best audio */
    PREMIUM,
}
