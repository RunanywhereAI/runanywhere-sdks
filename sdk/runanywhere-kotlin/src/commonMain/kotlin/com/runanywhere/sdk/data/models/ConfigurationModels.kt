package com.runanywhere.sdk.data.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import com.runanywhere.sdk.utils.getCurrentTimeMillis

/**
 * Configuration data models
 * One-to-one translation from iOS Swift configuration models to Kotlin
 */

/**
 * SDK Initialization Parameters
 * Used during SDK initialization
 */
data class SDKInitParams(
    val apiKey: String,
    val baseURL: String? = null,
    val environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
    val configuration: ConfigurationData? = null
)

/**
 * Configuration source enumeration
 * Equivalent to iOS ConfigurationSource enum
 */
enum class ConfigurationSource {
    REMOTE,
    CONSUMER,
    DEFAULTS
}

/**
 * SDK Environment enumeration
 * Equivalent to iOS SDKEnvironment enum
 */
enum class SDKEnvironment {
    DEVELOPMENT,
    STAGING,
    PRODUCTION
}

/**
 * Main configuration data class
 * One-to-one translation from iOS ConfigurationData
 */
@Serializable
data class ConfigurationData(
    val id: String,
    @SerialName("api_key")
    val apiKey: String,
    @SerialName("base_url")
    val baseURL: String,
    val environment: SDKEnvironment,
    val source: ConfigurationSource,
    @SerialName("last_updated")
    val lastUpdated: Long,

    // Nested configurations matching iOS exactly
    val routing: RoutingConfiguration,
    val generation: GenerationConfiguration,
    val storage: StorageConfiguration,
    val api: APIConfiguration,
    val download: ModelDownloadConfiguration,
    val hardware: HardwareConfiguration? = null
) {
    companion object {
        fun defaultConfiguration(apiKey: String): ConfigurationData {
            return ConfigurationData(
                id = "default",
                apiKey = apiKey,
                baseURL = "https://api.runanywhere.ai",
                environment = SDKEnvironment.DEVELOPMENT,
                source = ConfigurationSource.DEFAULTS,
                lastUpdated = getCurrentTimeMillis(),
                routing = RoutingConfiguration.defaults(),
                generation = GenerationConfiguration.defaults(),
                storage = StorageConfiguration.defaults(),
                api = APIConfiguration.defaults(),
                download = ModelDownloadConfiguration.defaults(),
                hardware = null
            )
        }

        fun default(apiKey: String): ConfigurationData = defaultConfiguration(apiKey)
    }
}

/**
 * Routing configuration
 * Equivalent to iOS RoutingConfiguration
 */
@Serializable
data class RoutingConfiguration(
    @SerialName("prefer_local")
    val preferLocal: Boolean = true,
    @SerialName("fallback_to_cloud")
    val fallbackToCloud: Boolean = true,
    @SerialName("model_priority")
    val modelPriority: List<String> = emptyList(),
    @SerialName("cost_threshold")
    val costThreshold: Double = 0.01,
    @SerialName("latency_threshold_ms")
    val latencyThresholdMs: Long = 5000
) {
    companion object {
        fun defaults() = RoutingConfiguration()
    }
}

/**
 * Generation configuration
 * Equivalent to iOS GenerationConfiguration
 */
@Serializable
data class GenerationConfiguration(
    @SerialName("max_tokens")
    val maxTokens: Int = 4096,
    val temperature: Float = 0.7f,
    @SerialName("top_p")
    val topP: Float = 0.9f,
    @SerialName("top_k")
    val topK: Int = 50,
    @SerialName("frequency_penalty")
    val frequencyPenalty: Float = 0.0f,
    @SerialName("presence_penalty")
    val presencePenalty: Float = 0.0f,
    @SerialName("stop_sequences")
    val stopSequences: List<String> = emptyList()
) {
    companion object {
        fun defaults() = GenerationConfiguration()
    }
}

/**
 * Storage configuration
 * Equivalent to iOS StorageConfiguration
 */
@Serializable
data class StorageConfiguration(
    @SerialName("cache_size_mb")
    val cacheSizeMB: Long = 512,
    @SerialName("model_cache_size_mb")
    val modelCacheSizeMB: Long = 2048,
    @SerialName("auto_cleanup")
    val autoCleanup: Boolean = true,
    @SerialName("cleanup_interval_hours")
    val cleanupIntervalHours: Int = 24,
    @SerialName("max_log_size_mb")
    val maxLogSizeMB: Long = 50
) {
    companion object {
        fun defaults() = StorageConfiguration()
    }
}

/**
 * API configuration
 * Equivalent to iOS APIConfiguration
 */
@Serializable
data class APIConfiguration(
    @SerialName("timeout_seconds")
    val timeoutSeconds: Int = 30,
    @SerialName("retry_attempts")
    val retryAttempts: Int = 3,
    @SerialName("retry_delay_ms")
    val retryDelayMs: Long = 1000,
    @SerialName("enable_logging")
    val enableLogging: Boolean = true,
    @SerialName("log_level")
    val logLevel: String = "INFO"
) {
    companion object {
        fun defaults() = APIConfiguration()
    }
}

/**
 * Model download configuration
 * Equivalent to iOS ModelDownloadConfiguration
 */
@Serializable
data class ModelDownloadConfiguration(
    @SerialName("parallel_downloads")
    val parallelDownloads: Int = 2,
    @SerialName("chunk_size_kb")
    val chunkSizeKB: Int = 1024,
    @SerialName("retry_attempts")
    val retryAttempts: Int = 3,
    @SerialName("verify_checksums")
    val verifyChecksums: Boolean = true,
    @SerialName("auto_resume")
    val autoResume: Boolean = true
) {
    companion object {
        fun defaults() = ModelDownloadConfiguration()
    }
}

/**
 * Hardware configuration
 * Equivalent to iOS HardwareConfiguration
 */
@Serializable
data class HardwareConfiguration(
    @SerialName("use_gpu")
    val useGPU: Boolean = true,
    @SerialName("gpu_layers")
    val gpuLayers: Int = -1, // -1 means auto-detect
    @SerialName("thread_count")
    val threadCount: Int = 0, // 0 means auto-detect
    @SerialName("memory_limit_mb")
    val memoryLimitMB: Long = 0, // 0 means no limit
    @SerialName("enable_metal")
    val enableMetal: Boolean = false, // Android specific: would be Vulkan
    @SerialName("enable_opencl")
    val enableOpenCL: Boolean = true
)

/**
 * Configuration update request
 * Used for partial configuration updates
 */
@Serializable
data class ConfigurationUpdateRequest(
    val routing: RoutingConfiguration? = null,
    val generation: GenerationConfiguration? = null,
    val storage: StorageConfiguration? = null,
    val api: APIConfiguration? = null,
    val download: ModelDownloadConfiguration? = null,
    val hardware: HardwareConfiguration? = null
)

/**
 * Configuration sync status
 * Equivalent to iOS ConfigurationSyncStatus
 */
enum class ConfigurationSyncStatus {
    IDLE,
    SYNCING,
    SUCCESS,
    FAILED
}

/**
 * Configuration sync result
 * Used to track sync operations
 */
data class ConfigurationSyncResult(
    val status: ConfigurationSyncStatus,
    val timestamp: Long,
    val error: String? = null,
    val configurationId: String? = null
)
