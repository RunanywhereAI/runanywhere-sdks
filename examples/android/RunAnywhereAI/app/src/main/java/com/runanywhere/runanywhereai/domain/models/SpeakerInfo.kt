package com.runanywhere.runanywhereai.domain.models

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.runanywhere.sdk.events.SpeakerInfo as SDKSpeakerInfo

/**
 * Information about a speaker in the transcript
 * UI-specific extension of SDK's SpeakerInfo with color for display
 */
data class SpeakerInfo(
    val id: String,
    val name: String,
    val confidence: Float,
    val color: Long // Color for UI display
) {
    companion object {
        /**
         * Convert SDK's SpeakerInfo to app's UI-specific version
         * Assigns a consistent color based on speaker ID
         */
        fun fromSDK(sdkSpeaker: SDKSpeakerInfo): SpeakerInfo {
            return SpeakerInfo(
                id = sdkSpeaker.id,
                name = sdkSpeaker.name ?: "Speaker ${sdkSpeaker.id}",
                confidence = sdkSpeaker.confidence ?: 1.0f,
                color = generateColorForSpeaker(sdkSpeaker.id)
            )
        }

        /**
         * Generate a consistent color for a speaker based on their ID
         */
        private fun generateColorForSpeaker(speakerId: String): Long {
            // Define a palette of distinct colors for speakers
            val colors = listOf(
                Color(0xFF2196F3), // Blue
                Color(0xFF4CAF50), // Green
                Color(0xFFFF9800), // Orange
                Color(0xFF9C27B0), // Purple
                Color(0xFFF44336), // Red
                Color(0xFF009688), // Teal
                Color(0xFFFFEB3B), // Yellow
                Color(0xFFE91E63)  // Pink
            )

            // Use hash to consistently assign color to speaker
            val hash = speakerId.hashCode()
            val colorIndex = (hash and 0x7FFFFFFF) % colors.size
            return colors[colorIndex].toArgb().toLong()
        }
    }
}
