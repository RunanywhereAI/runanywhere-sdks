package com.runanywhere.sdk.public.extensions

import kotlinx.serialization.Serializable

/**
 * Extension types for RunAnywhere SDK
 * Simple placeholder types to satisfy interface requirements
 */

@Serializable
data class ComponentInitializationConfig(
    val componentType: String,
    val modelId: String? = null,
    val priority: Int = 0
)

@Serializable
data class ComponentInitializationResult(
    val success: Boolean,
    val error: String? = null,
    val initTime: Long = 0
)

@Serializable
data class ConversationConfiguration(
    val id: String,
    val systemPrompt: String? = null,
    val maxTokens: Int = 1000
)

@Serializable
data class ConversationSession(
    val id: String,
    val configuration: ConversationConfiguration,
    val startTime: Long = System.currentTimeMillis()
)

@Serializable
data class CostTrackingConfig(
    val enabled: Boolean = true,
    val detailedBreakdown: Boolean = false,
    val alertThreshold: Float? = null
)

@Serializable
data class CostStatistics(
    val totalCost: Float = 0.0f,
    val tokenCount: Int = 0,
    val requestCount: Int = 0,
    val period: TimePeriod = TimePeriod.DAILY
) {
    enum class TimePeriod {
        HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY
    }
}

@Serializable
data class PipelineResult(
    val success: Boolean,
    val outputs: Map<String, String> = emptyMap(),
    val error: String? = null
)

@Serializable
data class RoutingPolicy(
    val preferOnDevice: Boolean = true,
    val maxLatency: Int? = null,
    val costOptimization: Boolean = true
)

// Voice-related types
@Serializable
data class STTOptions(
    val language: String = "en",
    val enableVAD: Boolean = true,
    val enablePunctuation: Boolean = true,
    val enableWordTimestamps: Boolean = false,
    val enableSpeakerDiarization: Boolean = false,
    val customVocabulary: List<String>? = null,
    val audioFormat: String = "PCM_16BIT",
    val sampleRate: Int = 16000
)

@Serializable
data class STTResult(
    val text: String,
    val confidence: Float,
    val language: String,
    val duration: Double,
    val wordTimestamps: List<WordTimestamp>? = null,
    val speakerSegments: List<SpeakerSegment>? = null,
    val processingTime: Double,
    val modelUsed: String
)

@Serializable
data class WordTimestamp(
    val word: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float
)

@Serializable
data class SpeakerSegment(
    val speakerId: String,
    val startTime: Double,
    val endTime: Double,
    val text: String
)
