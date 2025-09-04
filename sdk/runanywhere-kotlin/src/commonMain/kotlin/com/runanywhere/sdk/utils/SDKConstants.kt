package com.runanywhere.sdk.utils

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString

/**
 * SDK Constants Management
 * Single source of truth for all SDK constants, URLs, and configuration
 * Environment-specific values loaded from external config files
 */
object SDKConstants {

    // Configuration holder - will be populated from external config
    private var config: SDKConfig = SDKConfig()

    // JSON parser for config files
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * Initialize constants from configuration string
     * This should be called during SDK initialization with the appropriate config
     */
    fun loadConfiguration(configJson: String) {
        config = json.decodeFromString(configJson)
    }

    /**
     * Initialize with default development configuration
     * Used when no config is provided
     */
    fun loadDefaultConfiguration() {
        config = SDKConfig() // Uses default empty values
    }

    // MARK: - SDK Information
    const val VERSION = "0.1.0"
    val USER_AGENT get() = "RunAnywhere-Kotlin-SDK/${VERSION}"
    const val SDK_NAME = "runanywhere-kotlin"

    // MARK: - Environment Configuration
    enum class Environment {
        DEVELOPMENT,
        STAGING,
        PRODUCTION
    }

    val ENVIRONMENT: Environment get() = config.environment

    // MARK: - Base URLs (loaded from config)
    val BASE_URL: String get() = config.apiBaseUrl
    val CDN_BASE_URL: String get() = config.cdnBaseUrl
    val TELEMETRY_URL: String get() = config.telemetryUrl
    val ANALYTICS_URL: String get() = config.analyticsUrl

    // MARK: - API Keys (loaded from config)
    val DEFAULT_API_KEY: String get() = config.defaultApiKey

    // MARK: - Model Download URLs (loaded from config)
    object ModelUrls {
        // Language Models
        val LLAMA_3_2_1B: String get() = config.modelUrls.llama32_1b
        val LLAMA_3_2_3B: String get() = config.modelUrls.llama32_3b
        val SMOLLM2_1_7B: String get() = config.modelUrls.smollm2_17b
        val SMOLLM2_360M: String get() = config.modelUrls.smollm2_360m
        val QWEN_2_5_0_5B: String get() = config.modelUrls.qwen25_05b
        val QWEN_2_5_1_5B: String get() = config.modelUrls.qwen25_15b
        val LFM2_350M_Q4: String get() = config.modelUrls.lfm2_350m_q4
        val LFM2_350M_Q8: String get() = config.modelUrls.lfm2_350m_q8

        // Speech Models
        val WHISPER_TINY: String get() = config.modelUrls.whisperTiny
        val WHISPER_BASE: String get() = config.modelUrls.whisperBase
        val WHISPER_SMALL: String get() = config.modelUrls.whisperSmall
        val WHISPER_MEDIUM: String get() = config.modelUrls.whisperMedium
        val WHISPER_LARGE: String get() = config.modelUrls.whisperLarge
    }

    // MARK: - API Endpoints
    object API {
        // Authentication
        const val AUTHENTICATE = "/v1/auth/token"
        const val REFRESH_TOKEN = "/v1/auth/refresh"
        const val LOGOUT = "/v1/auth/logout"

        // Configuration
        const val CONFIGURATION = "/v1/config"
        const val USER_PREFERENCES = "/v1/user/preferences"

        // Models
        const val MODELS = "/v1/models"
        const val MODEL_DOWNLOAD = "/v1/models/{id}/download"
        const val MODEL_INFO = "/v1/models/{id}"

        // Device & Health
        const val HEALTH_CHECK = "/v1/health"
        const val DEVICE_INFO = "/v1/device"
        const val DEVICE_REGISTER = "/v1/device/register"

        // Generation
        const val GENERATE = "/v1/generate"
        const val GENERATION_HISTORY = "/v1/user/history"

        // Telemetry
        const val TELEMETRY_EVENTS = "/v1/telemetry/events"
        const val TELEMETRY_BATCH = "/v1/telemetry/batch"

        // Speech-to-Text Analytics
        const val STT_ANALYTICS = "/v1/analytics/stt"
        const val STT_METRICS = "/v1/analytics/stt/metrics"
    }

    // MARK: - Configuration Defaults
    object Defaults {
        // Network
        const val REQUEST_TIMEOUT_MS = 30000L
        const val CONNECT_TIMEOUT_MS = 15000L
        const val READ_TIMEOUT_MS = 30000L
        const val RETRY_ATTEMPTS = 3
        const val RETRY_DELAY_MS = 1000L

        // Database
        const val DATABASE_NAME = "runanywhere.db"
        const val DATABASE_VERSION = 1

        // Telemetry
        const val TELEMETRY_BATCH_SIZE = 50
        const val TELEMETRY_UPLOAD_INTERVAL_MS = 300000L
        const val TELEMETRY_RETRY_ATTEMPTS = 3
        const val TELEMETRY_MAX_EVENTS = 1000

        // Model Management
        const val MAX_MODEL_SIZE_BYTES = 2000000000L
        const val MODEL_DOWNLOAD_CHUNK_SIZE = 8192
        const val MAX_CONCURRENT_DOWNLOADS = 2

        // STT Configuration
        const val STT_SAMPLE_RATE = 16000
        const val STT_CHANNELS = 1
        const val STT_BITS_PER_SAMPLE = 16
        const val STT_FRAME_SIZE_MS = 20
        const val STT_BUFFER_SIZE_MS = 300

        // VAD Configuration
        const val VAD_SAMPLE_RATE = 16000
        const val VAD_FRAME_LENGTH_MS = 30
        const val VAD_MIN_SILENCE_DURATION_MS = 500
        const val VAD_MIN_SPEECH_DURATION_MS = 100

        // Authentication
        const val AUTH_TOKEN_REFRESH_THRESHOLD_SECONDS = 300L
        const val MAX_AUTH_RETRY_ATTEMPTS = 3

        // Device Info
        const val DEVICE_INFO_UPDATE_INTERVAL_MS = 60000L
        const val MEMORY_PRESSURE_UPDATE_INTERVAL_MS = 5000L
    }

    // MARK: - Storage Paths
    object Storage {
        const val BASE_DIRECTORY = "runanywhere"
        const val MODELS_DIRECTORY = "$BASE_DIRECTORY/models"
        const val CACHE_DIRECTORY = "$BASE_DIRECTORY/cache"
        const val TEMP_DIRECTORY = "$BASE_DIRECTORY/temp"
        const val LOGS_DIRECTORY = "$BASE_DIRECTORY/logs"

        const val LANGUAGE_MODELS_DIR = "$MODELS_DIRECTORY/language"
        const val SPEECH_MODELS_DIR = "$MODELS_DIRECTORY/speech"
        const val VISION_MODELS_DIR = "$MODELS_DIRECTORY/vision"

        const val NETWORK_CACHE_DIR = "$CACHE_DIRECTORY/network"
        const val MODEL_CACHE_DIR = "$CACHE_DIRECTORY/models"
        const val TELEMETRY_CACHE_DIR = "$CACHE_DIRECTORY/telemetry"
    }

    // MARK: - Secure Storage Keys
    object SecureStorage {
        const val KEYSTORE_ALIAS = "runanywhere_sdk_keystore"
        const val SHARED_PREFS_NAME = "runanywhere_secure_prefs"

        const val ACCESS_TOKEN_KEY = "access_token"
        const val REFRESH_TOKEN_KEY = "refresh_token"
        const val API_KEY_KEY = "api_key"
        const val DEVICE_ID_KEY = "device_id"
        const val USER_PREFERENCES_KEY = "user_preferences"
    }

    // MARK: - Development Mode
    object Development {
        val MOCK_DELAY_MS: Long get() = if (config.environment == Environment.DEVELOPMENT) 500L else 0L
        val ENABLE_VERBOSE_LOGGING: Boolean get() = config.enableVerboseLogging
        val ENABLE_MOCK_SERVICES: Boolean get() = config.enableMockServices

        const val MOCK_DEVICE_ID_PREFIX = "dev-device-"
        const val MOCK_SESSION_ID_PREFIX = "dev-session-"
        const val MOCK_USER_ID_PREFIX = "dev-user-"
    }

    // MARK: - Feature Flags
    object Features {
        val ENABLE_ON_DEVICE_INFERENCE: Boolean get() = config.features.onDeviceInference
        val ENABLE_CLOUD_FALLBACK: Boolean get() = config.features.cloudFallback
        val ENABLE_TELEMETRY: Boolean get() = config.features.telemetry
        val ENABLE_ANALYTICS: Boolean get() = config.features.analytics
        val ENABLE_DEBUG_LOGGING: Boolean get() = config.features.debugLogging
        val ENABLE_PERFORMANCE_MONITORING: Boolean get() = config.features.performanceMonitoring
        val ENABLE_CRASH_REPORTING: Boolean get() = config.features.crashReporting
        val ENABLE_VAD: Boolean get() = config.features.vad
        val ENABLE_STT_ANALYTICS: Boolean get() = config.features.sttAnalytics
        val ENABLE_REAL_TIME_STT: Boolean get() = config.features.realTimeStt
        val ENABLE_STT_CONFIDENCE_SCORING: Boolean get() = config.features.sttConfidenceScoring
    }

    // MARK: - Error Codes
    object ErrorCodes {
        const val NETWORK_UNAVAILABLE = 1001
        const val REQUEST_TIMEOUT = 1002
        const val AUTHENTICATION_FAILED = 1003
        const val INVALID_API_KEY = 1004

        const val MODEL_NOT_FOUND = 2001
        const val MODEL_DOWNLOAD_FAILED = 2002
        const val MODEL_LOAD_FAILED = 2003
        const val INSUFFICIENT_MEMORY = 2004

        const val STT_INITIALIZATION_FAILED = 3001
        const val STT_PROCESSING_FAILED = 3002
        const val AUDIO_RECORDING_FAILED = 3003
        const val VAD_INITIALIZATION_FAILED = 3004

        const val INITIALIZATION_FAILED = 5001
        const val CONFIGURATION_INVALID = 5002
        const val PERMISSION_DENIED = 5003
        const val STORAGE_UNAVAILABLE = 5004
    }
}

/**
 * SDK Configuration Model
 * This data class represents the complete configuration for the SDK
 */
@Serializable
data class SDKConfig(
    val environment: SDKConstants.Environment = SDKConstants.Environment.DEVELOPMENT,
    val apiBaseUrl: String = "",
    val cdnBaseUrl: String = "",
    val telemetryUrl: String = "",
    val analyticsUrl: String = "",
    val defaultApiKey: String = "",
    val enableVerboseLogging: Boolean = false,
    val enableMockServices: Boolean = false,
    val modelUrls: ModelUrlConfig = ModelUrlConfig(),
    val features: FeatureConfig = FeatureConfig()
)

@Serializable
data class ModelUrlConfig(
    // Language Models
    val llama32_1b: String = "",
    val llama32_3b: String = "",
    val smollm2_17b: String = "",
    val smollm2_360m: String = "",
    val qwen25_05b: String = "",
    val qwen25_15b: String = "",
    val lfm2_350m_q4: String = "",
    val lfm2_350m_q8: String = "",

    // Speech Models
    val whisperTiny: String = "",
    val whisperBase: String = "",
    val whisperSmall: String = "",
    val whisperMedium: String = "",
    val whisperLarge: String = ""
)

@Serializable
data class FeatureConfig(
    val onDeviceInference: Boolean = true,
    val cloudFallback: Boolean = true,
    val telemetry: Boolean = true,
    val analytics: Boolean = true,
    val debugLogging: Boolean = false,
    val performanceMonitoring: Boolean = true,
    val crashReporting: Boolean = false,
    val vad: Boolean = true,
    val sttAnalytics: Boolean = true,
    val realTimeStt: Boolean = true,
    val sttConfidenceScoring: Boolean = true
)
