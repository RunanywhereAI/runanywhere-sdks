package com.runanywhere.sdk.data.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

/**
 * Model info data models
 * One-to-one translation from iOS Swift model info models to Kotlin
 */

/**
 * LLM Framework enumeration
 * Equivalent to iOS LLMFramework enum
 */
enum class LLMFramework {
    LLAMA_CPP,
    WHISPER_CPP,
    ONNX,
    TENSORFLOW_LITE,
    CORE_ML, // Not applicable for Android, but keeping for parity
    PYTORCH_MOBILE,
    EXECUTORCH,
    MLX, // Not applicable for Android, but keeping for parity
    UNKNOWN
}

/**
 * Model category enumeration
 * Equivalent to iOS ModelCategory enum
 */
enum class ModelCategory {
    LARGE_LANGUAGE_MODEL,
    SPEECH_RECOGNITION,
    TEXT_TO_SPEECH,
    VOICE_ACTIVITY_DETECTION,
    VISION_LANGUAGE_MODEL,
    SPEAKER_DIARIZATION,
    WAKE_WORD_DETECTION,
    UNKNOWN
}

/**
 * Model format enumeration
 * Equivalent to iOS ModelFormat enum
 */
enum class ModelFormat {
    GGUF,
    GGML,
    ONNX,
    TFLITE,
    SAFETENSORS,
    PYTORCH,
    CORE_ML, // Not applicable for Android
    MLX, // Not applicable for Android
    UNKNOWN
}

/**
 * Model info data class
 * One-to-one translation from iOS ModelInfo
 */
@Serializable
data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val framework: LLMFramework,
    @SerialName("download_url")
    val downloadURL: String,
    @SerialName("local_path")
    val localPath: String? = null,
    @SerialName("download_size")
    val downloadSize: Long,
    @SerialName("memory_required")
    val memoryRequired: Long,
    @SerialName("compatible_frameworks")
    val compatibleFrameworks: List<String> = emptyList(),
    val version: String,
    val description: String,
    @SerialName("is_built_in")
    val isBuiltIn: Boolean = false,
    @SerialName("is_downloaded")
    val isDownloaded: Boolean = false,
    @SerialName("download_progress")
    val downloadProgress: Float = 0.0f,
    @SerialName("last_used")
    val lastUsed: Long? = null,
    @SerialName("checksum_sha256")
    val checksumSHA256: String? = null,
    val metadata: Map<String, String> = emptyMap(),
    @SerialName("created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @SerialName("updated_at")
    val updatedAt: Long = System.currentTimeMillis()
) {

    /**
     * Check if model file exists locally
     * Equivalent to iOS computed property
     */
    val isLocallyAvailable: Boolean
        get() = localPath != null && java.io.File(localPath).exists()

    /**
     * Get human-readable size string
     * Equivalent to iOS computed property
     */
    val sizeDescription: String
        get() = formatBytes(downloadSize)

    /**
     * Get memory usage description
     * Equivalent to iOS computed property
     */
    val memoryDescription: String
        get() = formatBytes(memoryRequired)

    /**
     * Check if model supports specific framework
     * Equivalent to iOS method
     */
    fun supportsFramework(framework: String): Boolean {
        return compatibleFrameworks.contains(framework) ||
               this.framework.name.equals(framework, ignoreCase = true)
    }

    private fun formatBytes(bytes: Long): String {
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var size = bytes.toDouble()
        var unitIndex = 0

        while (size >= 1024 && unitIndex < units.size - 1) {
            size /= 1024
            unitIndex++
        }

        return String.format("%.1f %s", size, units[unitIndex])
    }
}

/**
 * Model download status
 * Equivalent to iOS ModelDownloadStatus enum
 */
enum class ModelDownloadStatus {
    NOT_DOWNLOADED,
    DOWNLOADING,
    DOWNLOADED,
    FAILED,
    CANCELLED,
    PAUSED
}

/**
 * Model download info
 * Used to track download progress and status
 */
@Serializable
data class ModelDownloadInfo(
    @SerialName("model_id")
    val modelId: String,
    val status: ModelDownloadStatus,
    val progress: Float = 0.0f,
    @SerialName("downloaded_bytes")
    val downloadedBytes: Long = 0,
    @SerialName("total_bytes")
    val totalBytes: Long = 0,
    @SerialName("download_speed")
    val downloadSpeed: Long = 0, // bytes per second
    @SerialName("estimated_time_remaining")
    val estimatedTimeRemaining: Long = 0, // seconds
    val error: String? = null,
    @SerialName("started_at")
    val startedAt: Long? = null,
    @SerialName("completed_at")
    val completedAt: Long? = null
)

/**
 * Model capabilities
 * Describes what a model can do
 */
@Serializable
data class ModelCapabilities(
    @SerialName("supports_streaming")
    val supportsStreaming: Boolean = false,
    @SerialName("supports_function_calling")
    val supportsFunctionCalling: Boolean = false,
    @SerialName("supports_vision")
    val supportsVision: Boolean = false,
    @SerialName("supports_code_generation")
    val supportsCodeGeneration: Boolean = false,
    @SerialName("max_context_length")
    val maxContextLength: Int = 4096,
    @SerialName("supported_languages")
    val supportedLanguages: List<String> = emptyList(),
    @SerialName("input_modalities")
    val inputModalities: List<String> = listOf("text"),
    @SerialName("output_modalities")
    val outputModalities: List<String> = listOf("text")
)

/**
 * Model performance metrics
 * Used for model benchmarking and comparison
 */
@Serializable
data class ModelPerformanceMetrics(
    @SerialName("tokens_per_second")
    val tokensPerSecond: Float? = null,
    @SerialName("first_token_latency_ms")
    val firstTokenLatencyMs: Long? = null,
    @SerialName("memory_usage_mb")
    val memoryUsageMB: Long? = null,
    @SerialName("cpu_usage_percent")
    val cpuUsagePercent: Float? = null,
    @SerialName("gpu_usage_percent")
    val gpuUsagePercent: Float? = null,
    @SerialName("accuracy_score")
    val accuracyScore: Float? = null,
    @SerialName("benchmark_date")
    val benchmarkDate: Long? = null,
    @SerialName("device_info")
    val deviceInfo: String? = null
)

/**
 * Model registry entry
 * Complete model information including capabilities and metrics
 */
@Serializable
data class ModelRegistryEntry(
    val info: ModelInfo,
    val capabilities: ModelCapabilities,
    val performance: ModelPerformanceMetrics? = null,
    @SerialName("download_info")
    val downloadInfo: ModelDownloadInfo? = null
)

/**
 * Model search criteria
 * Used for filtering and searching models
 */
data class ModelSearchCriteria(
    val category: ModelCategory? = null,
    val framework: LLMFramework? = null,
    val format: ModelFormat? = null,
    val maxSize: Long? = null,
    val minAccuracy: Float? = null,
    val supportedLanguages: List<String>? = null,
    val capabilities: List<String>? = null,
    val isDownloaded: Boolean? = null,
    val searchQuery: String? = null
)
