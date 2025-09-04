package com.runanywhere.sdk.data.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import java.util.UUID

/**
 * Telemetry data models
 * One-to-one translation from iOS Swift telemetry models to Kotlin
 */

/**
 * Telemetry event type enumeration
 * Equivalent to iOS TelemetryEventType enum
 */
enum class TelemetryEventType {
    // SDK lifecycle events
    SDK_INITIALIZATION,
    SDK_CONFIGURATION_LOADED,
    SDK_AUTHENTICATION,
    SDK_ERROR,

    // Model events
    MODEL_DOWNLOAD_STARTED,
    MODEL_DOWNLOAD_COMPLETED,
    MODEL_DOWNLOAD_FAILED,
    MODEL_LOAD_STARTED,
    MODEL_LOAD_COMPLETED,
    MODEL_LOAD_FAILED,
    MODEL_UNLOAD,

    // Generation events
    GENERATION_STARTED,
    GENERATION_COMPLETED,
    GENERATION_FAILED,
    GENERATION_CANCELLED,

    // STT-specific events
    STT_INITIALIZATION,
    STT_MODEL_LOADED,
    STT_TRANSCRIPTION_STARTED,
    STT_TRANSCRIPTION_COMPLETED,
    STT_TRANSCRIPTION_FAILED,
    STT_VAD_DETECTED,
    STT_AUDIO_PROCESSED,

    // TTS events
    TTS_SYNTHESIS_STARTED,
    TTS_SYNTHESIS_COMPLETED,
    TTS_SYNTHESIS_FAILED,

    // Performance events
    PERFORMANCE_BENCHMARK,
    MEMORY_USAGE,
    CPU_USAGE,
    BATTERY_IMPACT,

    // User interaction events
    USER_INTERACTION,
    FEATURE_USAGE,

    // Custom events
    CUSTOM_EVENT
}

/**
 * Telemetry data class
 * One-to-one translation from iOS TelemetryData
 */
@Serializable
data class TelemetryData(
    val id: String = UUID.randomUUID().toString(),
    val type: TelemetryEventType,
    val name: String,
    val properties: Map<String, String> = emptyMap(),
    val metrics: Map<String, Double> = emptyMap(),

    // Session information
    @SerialName("session_id")
    val sessionId: String,
    @SerialName("user_id")
    val userId: String? = null,
    @SerialName("device_id")
    val deviceId: String,

    // Context information
    @SerialName("app_version")
    val appVersion: String? = null,
    @SerialName("sdk_version")
    val sdkVersion: String,
    val platform: String = "android",
    @SerialName("os_version")
    val osVersion: String,

    // Timing information
    val timestamp: Long = System.currentTimeMillis(),
    val duration: Long? = null, // milliseconds

    // Status information
    val success: Boolean = true,
    @SerialName("error_code")
    val errorCode: String? = null,
    @SerialName("error_message")
    val errorMessage: String? = null,

    // Synchronization status
    @SerialName("is_sent")
    val isSent: Boolean = false,
    @SerialName("sent_at")
    val sentAt: Long? = null,
    @SerialName("retry_count")
    val retryCount: Int = 0
) {

    /**
     * Get human-readable event description
     * Equivalent to iOS computed property
     */
    val eventDescription: String
        get() = buildString {
            append(name)
            if (properties.isNotEmpty()) {
                append(" (")
                append(properties.entries.joinToString(", ") { "${it.key}=${it.value}" })
                append(")")
            }
            duration?.let { append(" [${it}ms]") }
        }

    /**
     * Check if event needs retry
     * Based on retry policies
     */
    val needsRetry: Boolean
        get() = !isSent && retryCount < 3 && !success
}

/**
 * STT-specific telemetry data
 * Enhanced telemetry for speech-to-text operations
 */
@Serializable
data class STTTelemetryData(
    val baseEvent: TelemetryData,

    // Audio characteristics
    @SerialName("audio_duration_ms")
    val audioDurationMs: Long? = null,
    @SerialName("audio_sample_rate")
    val audioSampleRate: Int? = null,
    @SerialName("audio_channels")
    val audioChannels: Int? = null,
    @SerialName("audio_format")
    val audioFormat: String? = null,
    @SerialName("audio_size_bytes")
    val audioSizeBytes: Long? = null,

    // Model information
    @SerialName("model_id")
    val modelId: String? = null,
    @SerialName("model_size_mb")
    val modelSizeMB: Long? = null,
    @SerialName("model_type")
    val modelType: String? = null,

    // Processing metrics
    @SerialName("processing_time_ms")
    val processingTimeMs: Long? = null,
    @SerialName("first_token_latency_ms")
    val firstTokenLatencyMs: Long? = null,
    @SerialName("tokens_per_second")
    val tokensPerSecond: Float? = null,

    // Quality metrics
    @SerialName("confidence_score")
    val confidenceScore: Float? = null,
    @SerialName("word_count")
    val wordCount: Int? = null,
    @SerialName("character_count")
    val characterCount: Int? = null,

    // VAD information
    @SerialName("vad_detected")
    val vadDetected: Boolean? = null,
    @SerialName("vad_start_time_ms")
    val vadStartTimeMs: Long? = null,
    @SerialName("vad_end_time_ms")
    val vadEndTimeMs: Long? = null,
    @SerialName("silence_duration_ms")
    val silenceDurationMs: Long? = null,

    // Language information
    val language: String? = null,
    @SerialName("detected_language")
    val detectedLanguage: String? = null,
    @SerialName("language_confidence")
    val languageConfidence: Float? = null,

    // Resource usage
    @SerialName("memory_usage_mb")
    val memoryUsageMB: Long? = null,
    @SerialName("cpu_usage_percent")
    val cpuUsagePercent: Float? = null,
    @SerialName("gpu_usage_percent")
    val gpuUsagePercent: Float? = null,
    @SerialName("battery_drain_mah")
    val batteryDrainMAH: Float? = null
)

/**
 * Performance telemetry data
 * For benchmarking and optimization
 */
@Serializable
data class PerformanceTelemetryData(
    val baseEvent: TelemetryData,

    // System performance
    @SerialName("cpu_cores")
    val cpuCores: Int,
    @SerialName("total_memory_mb")
    val totalMemoryMB: Long,
    @SerialName("available_memory_mb")
    val availableMemoryMB: Long,
    @SerialName("gpu_type")
    val gpuType: String? = null,

    // Benchmark scores
    @SerialName("single_core_score")
    val singleCoreScore: Int? = null,
    @SerialName("multi_core_score")
    val multiCoreScore: Int? = null,
    @SerialName("gpu_score")
    val gpuScore: Int? = null,
    @SerialName("memory_bandwidth")
    val memoryBandwidth: Float? = null,

    // Thermal information
    @SerialName("thermal_state")
    val thermalState: String? = null,
    @SerialName("cpu_temperature")
    val cpuTemperature: Float? = null,
    @SerialName("battery_temperature")
    val batteryTemperature: Float? = null
)

/**
 * Error telemetry data
 * Enhanced error tracking
 */
@Serializable
data class ErrorTelemetryData(
    val baseEvent: TelemetryData,

    // Error classification
    @SerialName("error_category")
    val errorCategory: String,
    @SerialName("error_severity")
    val errorSeverity: String, // low, medium, high, critical
    @SerialName("error_type")
    val errorType: String,

    // Context information
    @SerialName("component_name")
    val componentName: String? = null,
    @SerialName("method_name")
    val methodName: String? = null,
    @SerialName("stack_trace")
    val stackTrace: String? = null,

    // Recovery information
    @SerialName("recovery_attempted")
    val recoveryAttempted: Boolean = false,
    @SerialName("recovery_successful")
    val recoverySuccessful: Boolean? = null,
    @SerialName("recovery_strategy")
    val recoveryStrategy: String? = null,

    // Impact assessment
    @SerialName("user_facing")
    val userFacing: Boolean = true,
    @SerialName("blocking")
    val blocking: Boolean = false,
    @SerialName("data_loss")
    val dataLoss: Boolean = false
)

/**
 * Session telemetry data
 * Track user sessions and usage patterns
 */
@Serializable
data class SessionTelemetryData(
    @SerialName("session_id")
    val sessionId: String,
    @SerialName("start_time")
    val startTime: Long,
    @SerialName("end_time")
    val endTime: Long? = null,
    val duration: Long? = null,

    // Session statistics
    @SerialName("events_count")
    val eventsCount: Int = 0,
    @SerialName("errors_count")
    val errorsCount: Int = 0,
    @SerialName("generations_count")
    val generationsCount: Int = 0,
    @SerialName("transcriptions_count")
    val transcriptionsCount: Int = 0,

    // Resource usage during session
    @SerialName("peak_memory_usage_mb")
    val peakMemoryUsageMB: Long? = null,
    @SerialName("average_cpu_usage")
    val averageCpuUsage: Float? = null,
    @SerialName("battery_drain_mah")
    val batteryDrainMAH: Float? = null,

    // Quality metrics
    @SerialName("average_confidence")
    val averageConfidence: Float? = null,
    @SerialName("success_rate")
    val successRate: Float? = null,

    // Context
    @SerialName("app_version")
    val appVersion: String? = null,
    @SerialName("sdk_version")
    val sdkVersion: String,
    @SerialName("device_id")
    val deviceId: String
)

/**
 * Telemetry batch for efficient transmission
 * Used to send multiple events in a single request
 */
@Serializable
data class TelemetryBatch(
    @SerialName("batch_id")
    val batchId: String = UUID.randomUUID().toString(),
    val events: List<TelemetryData>,
    @SerialName("created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("session_id")
    val sessionId: String,
    @SerialName("app_version")
    val appVersion: String? = null,
    @SerialName("sdk_version")
    val sdkVersion: String
) {

    val size: Int
        get() = events.size

    val timeSpan: Long
        get() = if (events.isEmpty()) 0 else events.maxOf { it.timestamp } - events.minOf { it.timestamp }
}
