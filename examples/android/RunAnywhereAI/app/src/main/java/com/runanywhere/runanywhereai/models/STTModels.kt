package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import com.runanywhere.sdk.core.types.InferenceFramework

/** STT recording mode. */
enum class STTMode {
    BATCH,
    LIVE,
}

/** Recording lifecycle state. */
enum class RecordingState {
    IDLE,
    RECORDING,
    PROCESSING,
}

/** Transcription performance metrics. */
@Immutable
data class TranscriptionMetrics(
    val confidence: Float = 0f,
    val audioDurationMs: Double = 0.0,
    val inferenceTimeMs: Double = 0.0,
    val detectedLanguage: String = "",
    val wordCount: Int = 0,
) {
    val realTimeFactor: Double
        get() = if (audioDurationMs > 0) inferenceTimeMs / audioDurationMs else 0.0
}

@Immutable
sealed interface STTUiState {
    data object Loading : STTUiState

    @Immutable
    data class Ready(
        val mode: STTMode = STTMode.BATCH,
        val recordingState: RecordingState = RecordingState.IDLE,
        val transcription: String = "",
        val isModelLoaded: Boolean = false,
        val selectedFramework: InferenceFramework? = null,
        val selectedModelName: String? = null,
        val selectedModelId: String? = null,
        val audioLevel: Float = 0f,
        val language: String = "en",
        val error: String? = null,
        val isTranscribing: Boolean = false,
        val metrics: TranscriptionMetrics? = null,
        val supportsLiveMode: Boolean = true,
    ) : STTUiState

    @Immutable
    data class Error(val message: String) : STTUiState
}

sealed interface STTEvent {
    data class ShowSnackbar(val message: String) : STTEvent
}
