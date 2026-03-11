package com.runanywhere.runanywhereai.models

import android.net.Uri
import androidx.compose.runtime.Immutable

@Immutable
sealed interface VLMUiState {
    data object Loading : VLMUiState

    @Immutable
    data class Ready(
        val isModelLoaded: Boolean = false,
        val loadedModelName: String? = null,
        val isProcessing: Boolean = false,
        val currentDescription: String = "",
        val error: String? = null,
        val selectedImageUri: Uri? = null,
        val isCameraAuthorized: Boolean = false,
        val isAutoStreamingEnabled: Boolean = false,
        val showModelSelection: Boolean = false,
        /** True when a single-shot capture result is being displayed (camera hidden). */
        val showingResult: Boolean = false,
    ) : VLMUiState

    @Immutable
    data class Error(val message: String) : VLMUiState
}

sealed interface VLMEvent {
    data class ShowSnackbar(val message: String) : VLMEvent
}
