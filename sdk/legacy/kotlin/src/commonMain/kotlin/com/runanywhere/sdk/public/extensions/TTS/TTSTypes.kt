/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for Text-to-Speech synthesis.
 * These are thin wrappers over C++ types in rac_tts_types.h
 *
 * Mirrors Swift TTSTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.TTS

import com.runanywhere.sdk.core.types.AudioFormat
import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.ComponentOutput
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKError
import kotlinx.serialization.Serializable

// MARK: - TTS Configuration

/**
 * Configuration for TTS component.
 * Mirrors Swift TTSConfiguration exactly.
 */
@Serializable
data class TTSConfiguration(
    /** Voice identifier to use for synthesis */
    val voice: String = DEFAULT_VOICE,
    /** Language for synthesis (BCP-47 format, e.g., "en-US") */
    val language: String = "en-US",
    /** Speaking rate (0.5 to 2.0, 1.0 is normal) */
    val speakingRate: Float = 1.0f,
    /** Speech pitch (0.5 to 2.0, 1.0 is normal) */
    val pitch: Float = 1.0f,
    /** Speech volume (0.0 to 1.0) */
    val volume: Float = 1.0f,
    /** Audio format for output */
    val audioFormat: AudioFormat = AudioFormat.PCM,
    /** Whether to use neural/premium voice if available */
    val useNeuralVoice: Boolean = true,
    /** Whether to enable SSML markup support */
    val enableSSML: Boolean = false,
) : ComponentConfiguration {
    override val modelId: String? get() = null
    override val preferredFramework: InferenceFramework? get() = null

    val componentType: SDKComponent get() = SDKComponent.TTS

    /**
     * Validate the configuration.
     * @throws SDKError if validation fails
     */
    fun validate() {
        require(speakingRate in 0.5f..2.0f) {
            throw SDKError.tts("Invalid speaking rate: $speakingRate. Must be between 0.5 and 2.0.")
        }
        require(pitch in 0.5f..2.0f) {
            throw SDKError.tts("Invalid pitch: $pitch. Must be between 0.5 and 2.0.")
        }
        require(volume in 0.0f..1.0f) {
            throw SDKError.tts("Invalid volume: $volume. Must be between 0.0 and 1.0.")
        }
    }

    /**
     * Builder pattern for TTSConfiguration.
     */
    class Builder(
        private var voice: String = DEFAULT_VOICE,
    ) {
        private var language: String = "en-US"
        private var speakingRate: Float = 1.0f
        private var pitch: Float = 1.0f
        private var volume: Float = 1.0f
        private var audioFormat: AudioFormat = AudioFormat.PCM
        private var useNeuralVoice: Boolean = true
        private var enableSSML: Boolean = false

        fun voice(voice: String) = apply { this.voice = voice }

        fun language(language: String) = apply { this.language = language }

        fun speakingRate(rate: Float) = apply { speakingRate = rate }

        fun pitch(pitch: Float) = apply { this.pitch = pitch }

        fun volume(volume: Float) = apply { this.volume = volume }

        fun audioFormat(format: AudioFormat) = apply { audioFormat = format }

        fun useNeuralVoice(enabled: Boolean) = apply { useNeuralVoice = enabled }

        fun enableSSML(enabled: Boolean) = apply { enableSSML = enabled }

        fun build() =
            TTSConfiguration(
                voice = voice,
                language = language,
                speakingRate = speakingRate,
                pitch = pitch,
                volume = volume,
                audioFormat = audioFormat,
                useNeuralVoice = useNeuralVoice,
                enableSSML = enableSSML,
            )
    }

    companion object {
        const val DEFAULT_VOICE = "default"
        const val DEFAULT_SAMPLE_RATE = 22050
        const val CD_QUALITY_SAMPLE_RATE = 44100

        fun builder(voice: String = DEFAULT_VOICE) = Builder(voice)
    }
}

// MARK: - TTS Options

/**
 * Options for text-to-speech synthesis.
 * Mirrors Swift TTSOptions exactly.
 */
@Serializable
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
    val sampleRate: Int = TTSConfiguration.DEFAULT_SAMPLE_RATE,
    /** Whether to use SSML markup */
    val useSSML: Boolean = false,
) {
    companion object {
        val DEFAULT = TTSOptions()

        /** Create options from TTSConfiguration */
        fun from(configuration: TTSConfiguration) =
            TTSOptions(
                voice = configuration.voice,
                language = configuration.language,
                rate = configuration.speakingRate,
                pitch = configuration.pitch,
                volume = configuration.volume,
                audioFormat = configuration.audioFormat,
                sampleRate =
                    if (configuration.audioFormat == AudioFormat.PCM) {
                        TTSConfiguration.DEFAULT_SAMPLE_RATE
                    } else {
                        TTSConfiguration.CD_QUALITY_SAMPLE_RATE
                    },
                useSSML = configuration.enableSSML,
            )
    }
}

// MARK: - TTS Output

/**
 * Output from Text-to-Speech synthesis.
 * Mirrors Swift TTSOutput exactly.
 */
@Serializable
data class TTSOutput(
    /** Synthesized audio data */
    val audioData: ByteArray,
    /** Audio format of the output */
    val format: AudioFormat,
    /** Duration of the audio in seconds */
    val duration: Double,
    /** Phoneme timestamps if available */
    val phonemeTimestamps: List<TTSPhonemeTimestamp>? = null,
    /** Processing metadata */
    val metadata: TTSSynthesisMetadata,
    /** Timestamp (required by ComponentOutput) */
    override val timestamp: Long = System.currentTimeMillis(),
) : ComponentOutput {
    /** Audio size in bytes */
    val audioSizeBytes: Int get() = audioData.size

    /** Whether the output has phoneme timing information */
    val hasPhonemeTimestamps: Boolean
        get() = phonemeTimestamps?.isNotEmpty() == true

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as TTSOutput
        return audioData.contentEquals(other.audioData) &&
            format == other.format &&
            duration == other.duration &&
            phonemeTimestamps == other.phonemeTimestamps &&
            metadata == other.metadata
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + format.hashCode()
        result = 31 * result + duration.hashCode()
        result = 31 * result + (phonemeTimestamps?.hashCode() ?: 0)
        result = 31 * result + metadata.hashCode()
        return result
    }
}

// MARK: - Supporting Types

/**
 * Synthesis metadata.
 * Mirrors Swift TTSSynthesisMetadata exactly.
 */
@Serializable
data class TTSSynthesisMetadata(
    /** Voice used for synthesis */
    val voice: String,
    /** Language used for synthesis */
    val language: String,
    /** Processing time in seconds */
    val processingTime: Double,
    /** Number of characters synthesized */
    val characterCount: Int,
) {
    /** Characters processed per second */
    val charactersPerSecond: Double
        get() = if (processingTime > 0) characterCount.toDouble() / processingTime else 0.0
}

/**
 * Phoneme timestamp information.
 * Mirrors Swift TTSPhonemeTimestamp exactly.
 */
@Serializable
data class TTSPhonemeTimestamp(
    /** The phoneme */
    val phoneme: String,
    /** Start time in seconds */
    val startTime: Double,
    /** End time in seconds */
    val endTime: Double,
) {
    /** Duration of the phoneme */
    val duration: Double get() = endTime - startTime
}

// MARK: - Speak Result

/**
 * Result from speak() - contains metadata only, no audio data.
 * Mirrors Swift TTSSpeakResult exactly.
 */
@Serializable
data class TTSSpeakResult(
    /** Duration of the spoken audio in seconds */
    val duration: Double,
    /** Audio format used */
    val format: AudioFormat,
    /** Audio size in bytes (0 for system TTS which plays directly) */
    val audioSizeBytes: Int,
    /** Synthesis metadata (voice, language, processing time, etc.) */
    val metadata: TTSSynthesisMetadata,
    /** Timestamp when speech completed */
    val timestamp: Long = System.currentTimeMillis(),
) {
    companion object {
        /** Create from TTSOutput (internal use) */
        internal fun from(output: TTSOutput) =
            TTSSpeakResult(
                duration = output.duration,
                format = output.format,
                audioSizeBytes = output.audioSizeBytes,
                metadata = output.metadata,
                timestamp = output.timestamp,
            )
    }
}
