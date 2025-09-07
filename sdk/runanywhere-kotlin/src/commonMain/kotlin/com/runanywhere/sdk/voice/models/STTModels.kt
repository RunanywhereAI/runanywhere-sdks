package com.runanywhere.sdk.voice.models

import kotlinx.serialization.Serializable

/**
 * Speech-to-Text Models
 * One-to-one mapping from iOS STTModels.swift
 */

/**
 * Input data for STT processing
 */
@Serializable
data class STTInput(
    val audioData: ByteArray,
    val sampleRate: Int = 16000,
    val language: String? = null,
    val options: STTOptions = STTOptions()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as STTInput
        return audioData.contentEquals(other.audioData) &&
                sampleRate == other.sampleRate &&
                language == other.language &&
                options == other.options
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + sampleRate
        result = 31 * result + (language?.hashCode() ?: 0)
        result = 31 * result + options.hashCode()
        return result
    }
}

/**
 * Output from STT processing
 */
@Serializable
data class STTOutput(
    val text: String,
    val confidence: Float = 0.0f,
    val language: String? = null,
    val segments: List<TranscriptionSegment> = emptyList(),
    val metadata: TranscriptionMetadata = TranscriptionMetadata()
)

/**
 * Options for STT processing
 */
@Serializable
data class STTOptions(
    val task: STTTask = STTTask.TRANSCRIBE,
    val beam: Int = 5,
    val maxLen: Int = 0,
    val wordTimestamps: Boolean = false,
    val withoutTimestamps: Boolean = false,
    val translateToEnglish: Boolean = false,
    val prompt: String? = null,
    val temperature: Float = 0.0f,
    val temperatureInc: Float = 0.2f,
    val compressionRatioThreshold: Float = 2.4f,
    val logProbThreshold: Float = -1.0f,
    val noSpeechThreshold: Float = 0.6f
)

/**
 * STT Task type
 */
@Serializable
enum class STTTask {
    TRANSCRIBE,
    TRANSLATE;

    val value: String
        get() = when (this) {
            TRANSCRIBE -> "transcribe"
            TRANSLATE -> "translate"
        }
}

/**
 * Transcription segment with timing information
 */
@Serializable
data class TranscriptionSegment(
    val id: Int,
    val seek: Int,
    val start: Float,
    val end: Float,
    val text: String,
    val tokens: List<Int> = emptyList(),
    val temperature: Float = 0.0f,
    val avgLogProb: Float = 0.0f,
    val compressionRatio: Float = 0.0f,
    val noSpeechProb: Float = 0.0f,
    val words: List<WordTimestamp> = emptyList()
)

/**
 * Word-level timestamp information
 */
@Serializable
data class WordTimestamp(
    val word: String,
    val start: Float,
    val end: Float,
    val probability: Float = 0.0f
)

/**
 * Metadata about the transcription
 */
@Serializable
data class TranscriptionMetadata(
    val audioLength: Float = 0.0f,
    val processingTime: Long = 0L,
    val modelVersion: String? = null,
    val device: String? = null,
    val audioProperties: AudioProperties? = null
)

/**
 * Audio properties for transcription
 */
@Serializable
data class AudioProperties(
    val sampleRate: Int = 16000,
    val channels: Int = 1,
    val bitDepth: Int = 16,
    val codec: String? = null,
    val duration: Float = 0.0f
)

/**
 * STT Model configuration
 */
@Serializable
data class STTModelConfig(
    val modelPath: String,
    val modelType: STTModelType = STTModelType.WHISPER,
    val modelSize: ModelSize = ModelSize.BASE,
    val quantization: Boolean = false,
    val multilingual: Boolean = true,
    val contextSize: Int = 1500,
    val encoderCoreMLPath: String? = null
)

/**
 * STT Model type
 */
@Serializable
enum class STTModelType {
    WHISPER,
    WAVE2VEC,
    CONFORMER,
    CUSTOM;

    val displayName: String
        get() = when (this) {
            WHISPER -> "Whisper"
            WAVE2VEC -> "Wave2Vec"
            CONFORMER -> "Conformer"
            CUSTOM -> "Custom"
        }
}

/**
 * Model size variants
 */
@Serializable
enum class ModelSize {
    TINY,
    BASE,
    SMALL,
    MEDIUM,
    LARGE;

    val displayName: String
        get() = when (this) {
            TINY -> "Tiny"
            BASE -> "Base"
            SMALL -> "Small"
            MEDIUM -> "Medium"
            LARGE -> "Large"
        }

    val approximateSize: Long
        get() = when (this) {
            TINY -> 39_000_000L // ~39MB
            BASE -> 74_000_000L // ~74MB
            SMALL -> 244_000_000L // ~244MB
            MEDIUM -> 769_000_000L // ~769MB
            LARGE -> 1_550_000_000L // ~1.55GB
        }
}

/**
 * STT processing state
 */
@Serializable
enum class STTState {
    IDLE,
    INITIALIZING,
    READY,
    PROCESSING,
    ERROR;

    val isActive: Boolean
        get() = this == PROCESSING

    val canProcess: Boolean
        get() = this == READY
}

/**
 * STT Error types
 */
@Serializable
sealed class STTError : Exception() {
    data class ModelNotFound(override val message: String) : STTError()
    data class AudioProcessingError(override val message: String) : STTError()
    data class TranscriptionError(override val message: String) : STTError()
    data class InitializationError(override val message: String) : STTError()
    data class LanguageNotSupported(val language: String) : STTError()
    data class InvalidInput(override val message: String) : STTError()
}
