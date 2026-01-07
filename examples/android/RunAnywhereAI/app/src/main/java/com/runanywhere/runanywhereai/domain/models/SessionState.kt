package com.runanywhere.runanywhereai.domain.models

/**
 * Session states for voice interaction
 * UI-specific enum that tracks the current state of the voice assistant
 * Matches iOS VoiceAssistantViewModel.SessionState
 */
enum class SessionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    LISTENING,
    PROCESSING,
    SPEAKING,
    ERROR,
}
