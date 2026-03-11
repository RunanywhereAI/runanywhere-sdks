package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable

/** Voice session lifecycle state. */
enum class VoiceAgentState {
    IDLE,
    LISTENING,
    THINKING,
    SPEAKING,
}

/** Model load state for voice pipeline components. */
enum class VoiceModelLoadState {
    NOT_LOADED,
    LOADING,
    LOADED,
    ERROR,
    ;

    val isLoaded: Boolean get() = this == LOADED
    val isLoading: Boolean get() = this == LOADING
}

/** Selected model info for a voice pipeline component. */
@Immutable
data class VoiceSelectedModel(
    val framework: String,
    val name: String,
    val modelId: String,
)

@Immutable
sealed interface VoiceUiState {
    data object Loading : VoiceUiState

    @Immutable
    data class Ready(
        val agentState: VoiceAgentState = VoiceAgentState.IDLE,
        val isListening: Boolean = false,
        val isSpeechDetected: Boolean = false,
        val currentTranscript: String = "",
        val assistantResponse: String = "",
        val streamingResponse: String = "",
        val audioLevel: Float = 0f,
        val error: String? = null,
        // Pipeline model selection
        val sttModel: VoiceSelectedModel? = null,
        val llmModel: VoiceSelectedModel? = null,
        val ttsModel: VoiceSelectedModel? = null,
        // Pipeline model load states
        val sttLoadState: VoiceModelLoadState = VoiceModelLoadState.NOT_LOADED,
        val llmLoadState: VoiceModelLoadState = VoiceModelLoadState.NOT_LOADED,
        val ttsLoadState: VoiceModelLoadState = VoiceModelLoadState.NOT_LOADED,
    ) : VoiceUiState {
        val allModelsLoaded: Boolean
            get() = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded
    }

    @Immutable
    data class Error(val message: String) : VoiceUiState
}

sealed interface VoiceEvent {
    data class ShowSnackbar(val message: String) : VoiceEvent
}
