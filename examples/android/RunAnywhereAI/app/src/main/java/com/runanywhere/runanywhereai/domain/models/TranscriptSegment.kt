package com.runanywhere.runanywhereai.domain.models

/**
 * Represents a segment of transcribed text
 */
data class TranscriptSegment(
    val id: String,
    val text: String,
    val timestamp: Long,
    val type: TranscriptType,
    val speaker: SpeakerInfo? = null,
    val confidence: Float = 1.0f,
    val thinking: String? = null
)

enum class TranscriptType {
    PARTIAL_USER,
    FINAL_USER,
    ASSISTANT
}
