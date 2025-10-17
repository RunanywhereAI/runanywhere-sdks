package com.runanywhere.sdk.data.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Configuration data models
 * Exact parity with iOS Swift configuration models - full feature translation
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
 * Exact match to iOS ConfigurationSource enum
 */
@Serializable
enum class ConfigurationSource {
    @SerialName("remote")
    REMOTE,
    @SerialName("consumer")
    CONSUMER,
    @SerialName("defaults")
    DEFAULTS
}

/**
 * Routing policy enumeration
 * Exact match to iOS RoutingPolicy enum
 */
@Serializable
enum class RoutingPolicy {
    @SerialName("device_only")
    DEVICE_ONLY,
    @SerialName("device_preferred")
    DEVICE_PREFERRED,
    @SerialName("cloud_preferred")
    CLOUD_PREFERRED,
    @SerialName("cloud_only")
    CLOUD_ONLY,
    @SerialName("custom")
    CUSTOM
}

/**
 * Privacy mode enumeration
 * Exact match to iOS PrivacyMode enum
 */
@Serializable
enum class PrivacyMode {
    @SerialName("standard")
    STANDARD,
    @SerialName("enhanced")
    ENHANCED,
    @SerialName("strict")
    STRICT
}

/**
 * Download policy enumeration
 * Exact match to iOS DownloadPolicy enum
 */
@Serializable
enum class DownloadPolicy {
    @SerialName("automatic")
    AUTOMATIC,
    @SerialName("wifi_only")
    WIFI_ONLY,
    @SerialName("manual")
    MANUAL,
    @SerialName("never")
    NEVER
}

/**
 * Cache eviction policy enumeration
 * Exact match to iOS CacheEvictionPolicy enum
 */
@Serializable
enum class CacheEvictionPolicy {
    @SerialName("lru")
    LEAST_RECENTLY_USED,
    @SerialName("lfu")
    LEAST_FREQUENTLY_USED,
    @SerialName("fifo")
    FIFO,
    @SerialName("largest_first")
    LARGEST_FIRST
}

/**
 * LLM Framework enumeration
 * Exact match to iOS LLMFramework enum
 */
@Serializable
enum class LLMFramework {
    @SerialName("llama_cpp")
    LLAMA_CPP,
    @SerialName("onnx")
    ONNX,
    @SerialName("core_ml")
    CORE_ML,
    @SerialName("tensorflow_lite")
    TENSORFLOW_LITE
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
 * Exact parity with iOS ConfigurationData struct
 */
@Serializable
data class ConfigurationData(
    /// Unique identifier for this configuration
    val id: String,

    /// Routing configuration
    val routing: RoutingConfiguration,

    /// Generation configuration
    val generation: GenerationConfiguration,

    /// Storage configuration (includes memory threshold)
    val storage: StorageConfiguration,

    /// API configuration (baseURL, timeouts, etc)
    val api: APIConfiguration,

    /// Download configuration
    val download: ModelDownloadConfiguration,

    /// Hardware preferences (optional)
    val hardware: HardwareConfiguration? = null,

    /// Debug mode flag
    @SerialName("debug_mode")
    val debugMode: Boolean = false,

    /// API key for authentication (optional - can be provided separately)
    @SerialName("api_key")
    val apiKey: String? = null,

    /// Whether user can override configuration
    @SerialName("allow_user_override")
    val allowUserOverride: Boolean = true,

    /// Configuration source
    val source: ConfigurationSource = ConfigurationSource.DEFAULTS,

    /// Metadata
    @SerialName("created_at")
    val createdAt: Long = getCurrentTimeMillis(),
    @SerialName("updated_at")
    val updatedAt: Long = getCurrentTimeMillis(),
    @SerialName("sync_pending")
    val syncPending: Boolean = false
) {

    /**
     * Mark configuration as updated
     * Equivalent to iOS markUpdated() extension method
     */
    fun markUpdated(): ConfigurationData {
        return copy(
            updatedAt = getCurrentTimeMillis(),
            syncPending = true
        )
    }
    companion object {
        /**
         * Create SDK default configuration
         * Exact match to iOS sdkDefaults(apiKey:) factory method
         */
        fun sdkDefaults(apiKey: String): ConfigurationData {
            return ConfigurationData(
                id = "default-${generateUUID()}",
                routing = RoutingConfiguration(),
                generation = GenerationConfiguration(),
                storage = StorageConfiguration(),
                api = APIConfiguration(),
                download = ModelDownloadConfiguration(),
                hardware = null,
                debugMode = false,
                apiKey = if (apiKey.isEmpty()) "dev-mode" else apiKey,
                allowUserOverride = true,
                source = ConfigurationSource.DEFAULTS,
                createdAt = getCurrentTimeMillis(),
                updatedAt = getCurrentTimeMillis(),
                syncPending = false
            )
        }

        /**
         * Legacy method for backward compatibility
         */
        fun defaultConfiguration(apiKey: String): ConfigurationData = sdkDefaults(apiKey)

        /**
         * Legacy method for backward compatibility
         */
        fun default(apiKey: String): ConfigurationData = sdkDefaults(apiKey)

        /**
         * Generate a simple UUID for configuration IDs
         */
        private fun generateUUID(): String {
            return "${getCurrentTimeMillis()}-${(0..9999).random()}"
        }
    }
}

/**
 * Routing configuration
 * Exact match to iOS RoutingConfiguration struct
 */
@Serializable
data class RoutingConfiguration(
    /// The routing policy to use
    val policy: RoutingPolicy = RoutingPolicy.DEVICE_ONLY,

    /// Whether cloud routing is enabled
    @SerialName("cloud_enabled")
    val cloudEnabled: Boolean = false,

    /// Privacy mode for routing decisions
    @SerialName("privacy_mode")
    val privacyMode: PrivacyMode = PrivacyMode.STANDARD,

    /// Custom routing rules (only used when policy is .custom)
    @SerialName("custom_rules")
    val customRules: Map<String, String> = emptyMap(),

    /// Maximum latency threshold for routing decisions (milliseconds)
    @SerialName("max_latency_threshold")
    val maxLatencyThreshold: Int? = null,

    /// Minimum confidence score for on-device execution (0.0 - 1.0)
    @SerialName("min_confidence_score")
    val minConfidenceScore: Double? = null
)

/**
 * Generation configuration
 * Exact match to iOS GenerationConfiguration struct
 */
@Serializable
data class GenerationConfiguration(
    /// Default generation settings
    val defaults: DefaultGenerationSettings = DefaultGenerationSettings(),

    /// Token budget configuration (optional)
    @SerialName("token_budget")
    val tokenBudget: TokenBudgetConfiguration? = null,

    /// Preferred frameworks for generation in order of preference
    @SerialName("framework_preferences")
    val frameworkPreferences: List<LLMFramework> = emptyList(),

    /// Maximum context length
    @SerialName("max_context_length")
    val maxContextLength: Int = 4096,

    /// Whether to enable thinking/reasoning extraction
    @SerialName("enable_thinking_extraction")
    val enableThinkingExtraction: Boolean = false,

    /// Pattern for thinking content extraction
    @SerialName("thinking_pattern")
    val thinkingPattern: String? = null
)

/**
 * Default settings for text generation
 * Exact match to iOS DefaultGenerationSettings struct
 */
@Serializable
data class DefaultGenerationSettings(
    /// Default temperature for generation
    val temperature: Double = 0.7,

    /// Default maximum tokens for generation
    @SerialName("max_tokens")
    val maxTokens: Int = 256,

    /// Default top-p value
    @SerialName("top_p")
    val topP: Double = 0.9,

    /// Default top-k value
    @SerialName("top_k")
    val topK: Int? = null,

    /// Default repetition penalty
    @SerialName("repetition_penalty")
    val repetitionPenalty: Double? = null,

    /// Default stop sequences
    @SerialName("stop_sequences")
    val stopSequences: List<String> = emptyList()
)

/**
 * Token budget configuration for managing usage
 * Exact match to iOS TokenBudgetConfiguration struct
 */
@Serializable
data class TokenBudgetConfiguration(
    /// Maximum tokens per request
    @SerialName("max_tokens_per_request")
    val maxTokensPerRequest: Int? = null,

    /// Maximum tokens per day
    @SerialName("max_tokens_per_day")
    val maxTokensPerDay: Int? = null,

    /// Maximum tokens per month
    @SerialName("max_tokens_per_month")
    val maxTokensPerMonth: Int? = null,

    /// Whether to enforce token limits strictly
    @SerialName("enforce_strictly")
    val enforceStrictly: Boolean = false
)

/**
 * Storage configuration
 * Exact match to iOS StorageConfiguration struct
 */
@Serializable
data class StorageConfiguration(
    /// Maximum cache size in bytes
    @SerialName("max_cache_size")
    val maxCacheSize: Long = 1_073_741_824L, // 1GB

    /// Cache eviction policy
    @SerialName("eviction_policy")
    val evictionPolicy: CacheEvictionPolicy = CacheEvictionPolicy.LEAST_RECENTLY_USED,

    /// Storage directory name
    @SerialName("directory_name")
    val directoryName: String = "RunAnywhere",

    /// Whether to enable automatic cleanup
    @SerialName("enable_auto_cleanup")
    val enableAutoCleanup: Boolean = true,

    /// Auto cleanup interval in seconds
    @SerialName("auto_cleanup_interval")
    val autoCleanupInterval: Double = 86400.0, // 24 hours

    /// Minimum free space to maintain (in bytes)
    @SerialName("minimum_free_space")
    val minimumFreeSpace: Long = 500_000_000L, // 500MB

    /// Whether to compress stored models
    @SerialName("enable_compression")
    val enableCompression: Boolean = false
)

/**
 * API configuration
 * Exact match to iOS APIConfiguration struct
 */
@Serializable
data class APIConfiguration(
    /// Base URL for API requests
    @SerialName("base_url")
    val baseURL: String = "https://api.runanywhere.ai",

    /// Timeout interval for requests (in seconds)
    @SerialName("timeout_interval")
    val timeoutInterval: Double = 30.0
) {
    companion object {
        /**
         * Create default API configuration matching iOS defaults
         */
        fun createDefault(baseURL: String = "https://api.runanywhere.ai"): APIConfiguration {
            return APIConfiguration(
                baseURL = baseURL,
                timeoutInterval = 30.0
            )
        }
    }
}

/**
 * Model download configuration
 * Exact match to iOS ModelDownloadConfiguration struct
 */
@Serializable
data class ModelDownloadConfiguration(
    /// Download policy
    val policy: DownloadPolicy = DownloadPolicy.AUTOMATIC,

    /// Maximum concurrent downloads
    @SerialName("max_concurrent_downloads")
    val maxConcurrentDownloads: Int = 3,

    /// Number of retry attempts
    @SerialName("retry_count")
    val retryCount: Int = 3,

    /// Download timeout in seconds
    val timeout: Double = 300.0,

    /// Enable background downloads
    @SerialName("enable_background_downloads")
    val enableBackgroundDownloads: Boolean = false
) {
    /**
     * Check if download is allowed
     * Exact match to iOS shouldAllowDownload method
     */
    fun shouldAllowDownload(isWiFi: Boolean = false, userConfirmed: Boolean = false): Boolean {
        return when (policy) {
            DownloadPolicy.AUTOMATIC -> true
            DownloadPolicy.WIFI_ONLY -> isWiFi
            DownloadPolicy.MANUAL -> userConfirmed
            DownloadPolicy.NEVER -> false
        }
    }
}

/**
 * Hardware configuration
 * Equivalent to iOS HardwareConfiguration - not defined in iOS yet but keeping for KMP compatibility
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
