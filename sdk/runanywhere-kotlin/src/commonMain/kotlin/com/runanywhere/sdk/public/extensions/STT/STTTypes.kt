/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for Speech-to-Text transcription.
 * These are thin wrappers over C++ types in rac_stt_types.h
 *
 * Mirrors Swift STTTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.STT

import com.runanywhere.sdk.core.types.AudioFormat
import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.ComponentOutput
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.serialization.Serializable

// MARK: - STT Configuration

/**
 * Configuration for STT component.
 * Mirrors Swift STTConfiguration exactly.
 */
@Serializable
data class STTConfiguration(
    override val modelId: String? = null,
    val language: String = "en-US",
    val sampleRate: Int = DEFAULT_SAMPLE_RATE,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val vocabularyList: List<String> = emptyList(),
    val maxAlternatives: Int = 1,
    val enableTimestamps: Boolean = true,
    override val preferredFramework: InferenceFramework? = null
) : ComponentConfiguration {

    val componentType: SDKComponent get() = SDKComponent.STT

    /**
     * Validate the configuration.
     * @throws IllegalArgumentException if validation fails
     */
    fun validate() {
        require(sampleRate in 1..48000) {
            "Sample rate must be between 1 and 48000 Hz"
        }
        require(maxAlternatives in 1..10) {
            "Max alternatives must be between 1 and 10"
        }
    }

    companion object {
        const val DEFAULT_SAMPLE_RATE = 16000
    }
}

// MARK: - STT Options

/**
 * Options for speech-to-text transcription.
 * Mirrors Swift STTOptions exactly.
 */
@Serializable
data class STTOptions(
    /** Language code for transcription (e.g., "en", "es", "fr") */
    val language: String = "en",

    /** Whether to auto-detect the spoken language */
    val detectLanguage: Boolean = false,

    /** Enable automatic punctuation in transcription */
    val enablePunctuation: Boolean = true,

    /** Enable speaker diarization (identify different speakers) */
    val enableDiarization: Boolean = false,

    /** Maximum number of speakers to identify (requires enableDiarization) */
    val maxSpeakers: Int? = null,

    /** Enable word-level timestamps */
    val enableTimestamps: Boolean = true,

    /** Custom vocabulary words to improve recognition */
    val vocabularyFilter: List<String> = emptyList(),

    /** Audio format of input data */
    val audioFormat: AudioFormat = AudioFormat.PCM,

    /** Sample rate of input audio (default: 16000 Hz for STT models) */
    val sampleRate: Int = STTConfiguration.DEFAULT_SAMPLE_RATE,

    /** Preferred framework for transcription (ONNX, etc.) */
    val preferredFramework: InferenceFramework? = null
) {
    companion object {
        /** Create options with default settings for a specific language */
        fun default(language: String = "en") = STTOptions(language = language)
    }
}

// MARK: - STT Output

/**
 * Output from Speech-to-Text (conforms to ComponentOutput).
 * Mirrors Swift STTOutput exactly.
 */
@Serializable
data class STTOutput(
    /** Transcribed text */
    val text: String,

    /** Confidence score (0.0 to 1.0) */
    val confidence: Float,

    /** Word-level timestamps if available */
    val wordTimestamps: List<WordTimestamp>? = null,

    /** Detected language if auto-detected */
    val detectedLanguage: String? = null,

    /** Alternative transcriptions if available */
    val alternatives: List<TranscriptionAlternative>? = null,

    /** Processing metadata */
    val metadata: TranscriptionMetadata,

    /** Timestamp (required by ComponentOutput) */
    override val timestamp: Long = System.currentTimeMillis()
) : ComponentOutput

// MARK: - Supporting Types

/**
 * Transcription metadata.
 * Mirrors Swift TranscriptionMetadata exactly.
 */
@Serializable
data class TranscriptionMetadata(
    val modelId: String,
    /** Processing time in seconds */
    val processingTime: Double,
    /** Audio length in seconds */
    val audioLength: Double
) {
    /** Processing time / audio length */
    val realTimeFactor: Double
        get() = if (audioLength > 0) processingTime / audioLength else 0.0
}

/**
 * Word timestamp information.
 * Mirrors Swift WordTimestamp exactly.
 */
@Serializable
data class WordTimestamp(
    val word: String,
    /** Start time in seconds */
    val startTime: Double,
    /** End time in seconds */
    val endTime: Double,
    val confidence: Float
)

/**
 * Alternative transcription.
 * Mirrors Swift TranscriptionAlternative exactly.
 */
@Serializable
data class TranscriptionAlternative(
    val text: String,
    val confidence: Float
)

// MARK: - STT Transcription Result

/**
 * Transcription result from service.
 * Mirrors Swift STTTranscriptionResult exactly.
 */
@Serializable
data class STTTranscriptionResult(
    val transcript: String,
    val confidence: Float? = null,
    val timestamps: List<TimestampInfo>? = null,
    val language: String? = null,
    val alternatives: List<AlternativeTranscription>? = null
) {
    @Serializable
    data class TimestampInfo(
        val word: String,
        val startTime: Double,
        val endTime: Double,
        val confidence: Float? = null
    )

    @Serializable
    data class AlternativeTranscription(
        val transcript: String,
        val confidence: Float
    )
}
