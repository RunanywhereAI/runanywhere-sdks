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
    val priority: Int = 0,
)

@Serializable
data class ComponentInitializationResult(
    val success: Boolean,
    val error: String? = null,
    val initTime: Long = 0,
)

@Serializable
data class ConversationConfiguration(
    val id: String,
    val systemPrompt: String? = null,
    val maxTokens: Int = 1000,
)

@Serializable
data class ConversationSession(
    val id: String,
    val configuration: ConversationConfiguration,
    val startTime: Long = System.currentTimeMillis(),
)

@Serializable
data class CostTrackingConfig(
    val enabled: Boolean = true,
    val detailedBreakdown: Boolean = false,
    val alertThreshold: Float? = null,
)

@Serializable
data class CostStatistics(
    val totalCost: Float = 0.0f,
    val tokenCount: Int = 0,
    val requestCount: Int = 0,
    val period: TimePeriod = TimePeriod.DAILY,
) {
    enum class TimePeriod {
        HOURLY,
        DAILY,
        WEEKLY,
        MONTHLY,
        YEARLY,
    }
}

@Serializable
data class PipelineResult(
    val success: Boolean,
    val outputs: Map<String, String> = emptyMap(),
    val error: String? = null,
)

// Note: RoutingPolicy has been moved to public/extensions/Cloud/CloudTypes.kt
// with full cloud routing support (RoutingMode, RoutingPolicy, RoutingDecision, etc.)

// Voice-related types are defined in their respective feature packages:
// - STTOptions, STTResult, etc. -> features/stt/STTModels.kt
// - SpeakerSegment -> features/speakerdiarization/SpeakerDiarizationModels.kt
// - WordTimestamp -> features/stt/STTModels.kt
