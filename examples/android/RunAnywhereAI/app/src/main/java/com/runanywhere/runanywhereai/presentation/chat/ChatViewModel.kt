package com.runanywhere.runanywhereai.presentation.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.model.ChatMessage
// import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
// import javax.inject.Inject

data class ChatUiState(
    val messages: List<ChatMessage> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

// @HiltViewModel
class ChatViewModel() : ViewModel() {

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    fun sendMessage(content: String) {
        viewModelScope.launch {
            // Add user message
            val userMessage = ChatMessage(
                content = content,
                isFromUser = true,
                timestamp = System.currentTimeMillis()
            )

            _uiState.value = _uiState.value.copy(
                messages = _uiState.value.messages + userMessage,
                isLoading = true,
                error = null
            )

            try {
                // TODO: Integrate with SDK for actual AI response
                // For now, simulate a response
                delay(1000) // Simulate processing time

                val aiResponse = ChatMessage(
                    content = "This is a mock response. SDK integration coming soon!",
                    isFromUser = false,
                    timestamp = System.currentTimeMillis()
                )

                _uiState.value = _uiState.value.copy(
                    messages = _uiState.value.messages + aiResponse,
                    isLoading = false
                )

            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = "Failed to get AI response: ${e.message}"
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }
}
