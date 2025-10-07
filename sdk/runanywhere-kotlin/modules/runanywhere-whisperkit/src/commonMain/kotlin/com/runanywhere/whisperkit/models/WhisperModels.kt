package com.runanywhere.whisperkit.models

import kotlinx.serialization.Serializable

/**
 * Whisper-specific model types
 * These are NOT generic STT model types - they are specific to WhisperKit implementation
 * The generic STT interfaces use simple string model IDs
 * This enum provides strongly-typed Whisper model variants matching iOS WhisperKit
 */
@Serializable
enum class WhisperModelType {
    TINY,
    BASE,
    SMALL,
    MEDIUM,
    LARGE,
    LARGE_V2,
    LARGE_V3;

    val modelName: String
        get() = when (this) {
            TINY -> "whisper-tiny"
            BASE -> "whisper-base"
            SMALL -> "whisper-small"
            MEDIUM -> "whisper-medium"
            LARGE -> "whisper-large"
            LARGE_V2 -> "whisper-large-v2"
            LARGE_V3 -> "whisper-large-v3"
        }

    val fileName: String
        get() = when (this) {
            TINY -> "ggml-tiny.bin"
            BASE -> "ggml-base.bin"
            SMALL -> "ggml-small.bin"
            MEDIUM -> "ggml-medium.bin"
            LARGE -> "ggml-large.bin"
            LARGE_V2 -> "ggml-large-v2.bin"
            LARGE_V3 -> "ggml-large-v3.bin"
        }

    val downloadUrl: String
        get() = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName"

    val approximateSizeMB: Int
        get() = when (this) {
            TINY -> 39
            BASE -> 74
            SMALL -> 142
            MEDIUM -> 462
            LARGE -> 1550
            LARGE_V2 -> 1550
            LARGE_V3 -> 1550
        }

    companion object {
        fun fromModelName(name: String): WhisperModelType? {
            return values().firstOrNull { it.modelName == name }
        }
    }
}

/**
 * Whisper-specific model information
 * Contains metadata specific to Whisper models, not generic STT models
 */
@Serializable
data class WhisperModelInfo(
    val type: WhisperModelType,
    val localPath: String? = null,
    val isDownloaded: Boolean = false,
    val downloadProgress: Float = 0f,
    val lastUsed: Long? = null
)

/**
 * Whisper-specific transcription options
 * These extend beyond generic STT options to include Whisper-specific parameters
 * Generic STT uses STTOptions; this provides Whisper-specific configuration
 */
@Serializable
data class WhisperTranscriptionOptions(
    val language: String = "auto",
    val enableTimestamps: Boolean = false,
    val temperature: Float = 0.0f,
    val suppressBlank: Boolean = true,
    val suppressNonSpeechTokens: Boolean = true,
    val maxInitialTimestamp: Float = 1.0f,
    val lengthPenalty: Float = 1.0f,
    val temperatureIncrementOnFallback: Float = 0.2f,
    val compressionRatioThreshold: Float = 2.4f,
    val logProbThreshold: Float = -1.0f,
    val noSpeechThreshold: Float = 0.6f,
    val condition: Boolean = true,
    val initialPrompt: String? = null,
    val detectLanguage: Boolean = true
)

/**
 * Whisper-specific transcription result
 * Extends generic STTTranscriptionResult with Whisper-specific metadata
 * Generic STT uses STTTranscriptionResult; this provides additional Whisper details
 */
@Serializable
data class WhisperTranscriptionResult(
    val text: String,
    val segments: List<TranscriptionSegment> = emptyList(),
    val language: String? = null,
    val confidence: Float = 0.0f,
    val duration: Double = 0.0,
    val timestamps: List<WordTimestamp>? = null
)

/**
 * Transcription segment with timing information
 */
@Serializable
data class TranscriptionSegment(
    val id: Int,
    val seek: Int,
    val start: Double,
    val end: Double,
    val text: String,
    val tokens: List<Int> = emptyList(),
    val temperature: Float = 0.0f,
    val avgLogProb: Float = 0.0f,
    val compressionRatio: Float = 0.0f,
    val noSpeechProb: Float = 0.0f
)

/**
 * Word-level timestamp
 */
@Serializable
data class WordTimestamp(
    val word: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float = 0.0f
)

/**
 * Whisper-specific service state
 * More detailed than generic STT ready/not-ready states
 * Allows tracking of Whisper-specific operations like model downloads
 */
@Serializable
enum class WhisperServiceState {
    UNINITIALIZED,
    INITIALIZING,
    DOWNLOADING_MODEL,
    LOADING_MODEL,
    READY,
    TRANSCRIBING,
    ERROR
}

/**
 * Whisper-specific errors
 * These extend beyond generic STT errors to cover Whisper-specific failure modes
 */
sealed class WhisperError : Exception() {
    data class ModelNotFound(override val message: String) : WhisperError()
    data class ModelDownloadFailed(override val message: String) : WhisperError()
    data class InitializationFailed(override val message: String) : WhisperError()
    data class TranscriptionFailed(override val message: String) : WhisperError()
    data class ServiceNotReady(override val message: String = "Whisper service is not ready") : WhisperError()
    data class InvalidAudioFormat(override val message: String) : WhisperError()
    data class NetworkError(override val message: String) : WhisperError()
}
