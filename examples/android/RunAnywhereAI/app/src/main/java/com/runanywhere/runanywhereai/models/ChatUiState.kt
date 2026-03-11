package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

@Immutable
sealed interface ChatUiState {
    data object Loading : ChatUiState

    @Immutable
    data class Ready(
        val messages: ImmutableList<ChatMessage> = persistentListOf(),
        val isGenerating: Boolean = false,
        val isModelLoaded: Boolean = false,
        val loadedModelName: String? = null,
        val currentModelSupportsLora: Boolean = false,
        val hasActiveLoraAdapter: Boolean = false,
        val currentConversation: Conversation? = null,
        val error: String? = null,
    ) : ChatUiState

    @Immutable
    data class Error(val message: String) : ChatUiState
}

sealed interface DialogState {
    data object None : DialogState
    data object ModelSelection : DialogState
    data object ConversationList : DialogState
    data object ChatDetails : DialogState
}

sealed interface ChatEvent {
    data class ShowSnackbar(val message: String) : ChatEvent
    data object ScrollToBottom : ChatEvent
}
