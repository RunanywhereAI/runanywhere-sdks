package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

// -- UI State --------------------------------------------------------------------

@Immutable
sealed interface SettingsUiState {

    data object Loading : SettingsUiState

    @Immutable
    data class Ready(
        // Generation settings
        val temperature: Float = 0.7f,
        val maxTokens: Int = 1000,
        val systemPrompt: String = "",

        // Tool calling
        val toolCallingEnabled: Boolean = false,
        val registeredToolNames: ImmutableList<String> = persistentListOf(),
        val isToolLoading: Boolean = false,

        // Storage overview
        val totalStorageSize: Long = 0L,
        val availableSpace: Long = 0L,
        val modelStorageSize: Long = 0L,
        val downloadedModels: ImmutableList<StoredModelInfo> = persistentListOf(),

        // Logging
        val analyticsLogToLocal: Boolean = false,

        // API configuration status (display only)
        val isApiKeyConfigured: Boolean = false,
        val isBaseURLConfigured: Boolean = false,
    ) : SettingsUiState

    @Immutable
    data class Error(val message: String) : SettingsUiState
}

// -- Supporting models -----------------------------------------------------------

@Immutable
data class StoredModelInfo(
    val id: String,
    val name: String,
    val size: Long,
)

@Immutable
data class GenerationSettings(
    val temperature: Float,
    val maxTokens: Int,
    val systemPrompt: String?,
)

// -- Dialog state ----------------------------------------------------------------

sealed interface SettingsDialogState {
    data object None : SettingsDialogState
    data object ApiConfiguration : SettingsDialogState
    data object RestartRequired : SettingsDialogState
    data class DeleteModel(val model: StoredModelInfo) : SettingsDialogState
}

// -- One-shot events -------------------------------------------------------------

sealed interface SettingsEvent {
    data class ShowSnackbar(val message: String) : SettingsEvent
}
