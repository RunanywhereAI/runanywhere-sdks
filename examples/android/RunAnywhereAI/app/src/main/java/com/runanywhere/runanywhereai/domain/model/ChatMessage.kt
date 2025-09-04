package com.runanywhere.runanywhereai.domain.model

/**
 * Represents a chat message in the conversation
 */
data class ChatMessage(
    val content: String,
    val isFromUser: Boolean,
    val timestamp: Long,
    val id: String = generateId()
) {
    companion object {
        private fun generateId(): String {
            return System.currentTimeMillis().toString() + (0..999).random()
        }
    }
}
