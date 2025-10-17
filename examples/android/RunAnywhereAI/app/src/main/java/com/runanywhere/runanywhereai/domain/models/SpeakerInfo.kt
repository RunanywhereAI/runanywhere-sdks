package com.runanywhere.runanywhereai.domain.models

/**
 * Information about a speaker in the transcript
 * TODO: This will be provided by the SDK's speaker diarization feature
 */
data class SpeakerInfo(
    val id: String,
    val name: String,
    val confidence: Float,
    val color: Long // Color for UI display
)
