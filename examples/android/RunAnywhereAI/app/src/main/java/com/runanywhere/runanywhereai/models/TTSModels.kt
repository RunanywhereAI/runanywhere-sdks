package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import com.runanywhere.sdk.core.types.InferenceFramework

@Immutable
sealed interface TTSUiState {
    data object Loading : TTSUiState

    @Immutable
    data class Ready(
        val inputText: String = "",
        val characterCount: Int = 0,
        val maxCharacters: Int = 5000,
        val isModelLoaded: Boolean = false,
        val selectedFramework: InferenceFramework? = null,
        val selectedModelName: String? = null,
        val selectedModelId: String? = null,
        val isGenerating: Boolean = false,
        val isPlaying: Boolean = false,
        val isSpeaking: Boolean = false,
        val hasGeneratedAudio: Boolean = false,
        val isSystemTTS: Boolean = false,
        val speed: Float = 1.0f,
        val audioDuration: Double? = null,
        val audioSize: Int? = null,
        val playbackProgress: Double = 0.0,
        val currentTime: Double = 0.0,
        val error: String? = null,
    ) : TTSUiState

    @Immutable
    data class Error(val message: String) : TTSUiState
}

sealed interface TTSEvent {
    data class ShowSnackbar(val message: String) : TTSEvent
}
