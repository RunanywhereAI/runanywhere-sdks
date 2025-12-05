package com.runanywhere.sdk.data.models

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.Contextual

/**
 * Telemetry data models
 * One-to-one translation from iOS Swift telemetry models to Kotlin
 */

/**
 * Platform-specific UUID generation
 */
expect fun generateUUID(): String

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
    MODEL_LOADED, // Alias for MODEL_LOAD_COMPLETED

    // Generation events
    GENERATION_STARTED,
    GENERATION_COMPLETED,
    GENERATION_FAILED,
    GENERATION_CANCELLED,

    // STT-specific events
    STT_INITIALIZATION,
    STT_MODEL_LOADED,
    STT_MODEL_LOAD_FAILED,
    STT_TRANSCRIPTION_STARTED,
    STT_TRANSCRIPTION_COMPLETED,
    STT_TRANSCRIPTION_FAILED,
    STT_STREAMING_UPDATE,
    STT_VAD_DETECTED,
    STT_AUDIO_PROCESSED,
    STT_EVENT,  // Generic STT event

    // TTS events
    TTS_MODEL_LOADED,
    TTS_MODEL_LOAD_FAILED,
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
 * Simple telemetry event data
 * Used for quick event tracking
 */
@Serializable
data class TelemetryEventData(
    val id: String = generateUUID(),
    val type: TelemetryEventType,
    val sessionId: String,
    val deviceId: String,
    val timestamp: Long = getCurrentTimeMillis(),
    val eventData: Map<String, @Contextual Any?> = emptyMap(),
    val success: Boolean = true,
    val duration: Long? = null
)

/**
 * Telemetry data class
 * One-to-one translation from iOS TelemetryData
 */
@Serializable
data class TelemetryData(
    val id: String = generateUUID(),
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
    val timestamp: Long = getCurrentTimeMillis(),
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
    val deviceId: String,
    @SerialName("created_at")
    val createdAt: Long = getCurrentTimeMillis()
)

/**
 * Telemetry batch for efficient transmission
 * Used to send multiple events in a single request
 */
@Serializable
data class TelemetryBatch(
    @SerialName("batch_id")
    val batchId: String = generateUUID(),
    val events: List<TelemetryData>,
    @SerialName("created_at")
    val createdAt: Long = getCurrentTimeMillis(),
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

/**
 * Typed telemetry event payload for API transmission (matches iOS TelemetryEventPayload)
 * Maps to backend SDKTelemetryEvent schema with strongly typed fields.
 * NO JSON properties dictionary - all fields are strongly typed.
 */
@Serializable
data class TelemetryEventPayload(
    // MARK: - Required Fields
    val id: String,
    @SerialName("event_type")
    val eventType: String,
    val timestamp: Long,
    @SerialName("created_at")
    val createdAt: Long,

    // MARK: - Session Tracking
    @SerialName("session_id")
    val sessionId: String? = null,

    // MARK: - Model Info
    @SerialName("model_id")
    val modelId: String? = null,
    @SerialName("model_name")
    val modelName: String? = null,
    val framework: String? = null,
    val modality: String? = null,  // "stt", "tts", "llm", etc.

    // MARK: - Device Info
    val device: String? = null,
    @SerialName("os_version")
    val osVersion: String? = null,
    val platform: String? = null,
    @SerialName("sdk_version")
    val sdkVersion: String? = null,

    // MARK: - Common Performance Metrics
    @SerialName("processing_time_ms")
    val processingTimeMs: Double? = null,
    val success: Boolean? = null,
    @SerialName("error_message")
    val errorMessage: String? = null,
    @SerialName("error_code")
    val errorCode: String? = null,

    // MARK: - LLM-specific Fields
    @SerialName("input_tokens")
    val inputTokens: Int? = null,
    @SerialName("output_tokens")
    val outputTokens: Int? = null,
    @SerialName("total_tokens")
    val totalTokens: Int? = null,
    @SerialName("tokens_per_second")
    val tokensPerSecond: Double? = null,
    @SerialName("time_to_first_token_ms")
    val timeToFirstTokenMs: Double? = null,
    @SerialName("prompt_eval_time_ms")
    val promptEvalTimeMs: Double? = null,
    @SerialName("generation_time_ms")
    val generationTimeMs: Double? = null,
    @SerialName("context_length")
    val contextLength: Int? = null,
    val temperature: Double? = null,
    @SerialName("max_tokens")
    val maxTokens: Int? = null,

    // MARK: - STT-specific Fields
    @SerialName("audio_duration_ms")
    val audioDurationMs: Double? = null,
    @SerialName("real_time_factor")
    val realTimeFactor: Double? = null,
    @SerialName("word_count")
    val wordCount: Int? = null,
    val confidence: Double? = null,
    val language: String? = null,
    @SerialName("is_streaming")
    val isStreaming: Boolean? = null,
    @SerialName("segment_index")
    val segmentIndex: Int? = null,

    // MARK: - TTS-specific Fields
    @SerialName("character_count")
    val characterCount: Int? = null,
    @SerialName("characters_per_second")
    val charactersPerSecond: Double? = null,
    @SerialName("audio_size_bytes")
    val audioSizeBytes: Int? = null,
    @SerialName("sample_rate")
    val sampleRate: Int? = null,
    val voice: String? = null,
    @SerialName("output_duration_ms")
    val outputDurationMs: Double? = null
)

/**
 * Batch telemetry request for API (matches iOS TelemetryBatchRequest)
 */
@Serializable
data class TelemetryBatchRequest(
    val events: List<TelemetryEventPayload>,
    @SerialName("device_id")
    val deviceId: String,
    val timestamp: Long = getCurrentTimeMillis()
)

/**
 * Batch telemetry response from API (matches iOS TelemetryBatchResponse)
 */
@Serializable
data class TelemetryBatchResponse(
    val success: Boolean,
    @SerialName("events_received")
    val eventsReceived: Int,
    @SerialName("events_stored")
    val eventsStored: Int,
    val errors: List<String>? = null
)
