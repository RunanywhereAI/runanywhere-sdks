package com.runanywhere.sdk.utils

// BuildConfig is platform-specific

/**
 * SDK Constants Management
 * Single source of truth for all SDK constants, URLs, and configuration
 * Environment-specific values based on build configuration
 */
object SDKConstants {

    // MARK: - SDK Information
    const val VERSION = "1.0.0"
    const val USER_AGENT = "RunAnywhere-Android-SDK/$VERSION"
    const val SDK_NAME = "runanywhere-android"

    // MARK: - Environment Configuration

    /**
     * Current environment based on build configuration
     * Defaults to DEVELOPMENT for debug builds
     */
    val ENVIRONMENT: Environment = Environment.DEVELOPMENT // Default to development

    enum class Environment {
        DEVELOPMENT,
        PRODUCTION
    }

    // MARK: - Base URLs

    /**
     * Base API URL based on current environment
     */
    const val DEFAULT_BASE_URL: String = "https://dev-api.runanywhere.ai"

    val BASE_URL: String = when (ENVIRONMENT) {
        Environment.DEVELOPMENT -> "https://dev-api.runanywhere.ai"
        Environment.PRODUCTION -> "https://api.runanywhere.ai"
    }

    /**
     * Base CDN URL for model downloads
     */
    val CDN_BASE_URL: String = when (ENVIRONMENT) {
        Environment.DEVELOPMENT -> "https://dev-cdn.runanywhere.ai"
        Environment.PRODUCTION -> "https://cdn.runanywhere.ai"
    }

    /**
     * Telemetry endpoint URL
     */
    val TELEMETRY_URL: String = when (ENVIRONMENT) {
        Environment.DEVELOPMENT -> "https://dev-telemetry.runanywhere.ai"
        Environment.PRODUCTION -> "https://telemetry.runanywhere.ai"
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

    // MARK: - Model Catalog URLs

    object ModelCatalog {
        // HuggingFace Base URLs
        const val HUGGINGFACE_BASE = "https://huggingface.co"

        // Language Models
        object Language {
            // Llama Models
            const val LLAMA_3_2_1B_Q6K = "$HUGGINGFACE_BASE/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf"
            const val LLAMA_3_2_3B_Q6K = "$HUGGINGFACE_BASE/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q6_K.gguf"

            // SmolLM Models
            const val SMOLLM2_1_7B_Q6K_L = "$HUGGINGFACE_BASE/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf"
            const val SMOLLM2_360M_Q8_0 = "$HUGGINGFACE_BASE/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"

            // Qwen Models
            const val QWEN_2_5_0_5B_Q6K = "$HUGGINGFACE_BASE/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf"
            const val QWEN_2_5_1_5B_Q6K = "$HUGGINGFACE_BASE/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf"

            // LiquidAI Models
            const val LFM2_350M_Q4K_M = "$HUGGINGFACE_BASE/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf"
            const val LFM2_350M_Q8_0 = "$HUGGINGFACE_BASE/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf"
        }

        // Speech Recognition Models
        object Speech {
            // Whisper Models
            const val WHISPER_TINY = "$HUGGINGFACE_BASE/openai/whisper-tiny/resolve/main/pytorch_model.bin"
            const val WHISPER_BASE = "$HUGGINGFACE_BASE/openai/whisper-base/resolve/main/pytorch_model.bin"
            const val WHISPER_SMALL = "$HUGGINGFACE_BASE/openai/whisper-small/resolve/main/pytorch_model.bin"
            const val WHISPER_MEDIUM = "$HUGGINGFACE_BASE/openai/whisper-medium/resolve/main/pytorch_model.bin"
            const val WHISPER_LARGE = "$HUGGINGFACE_BASE/openai/whisper-large/resolve/main/pytorch_model.bin"
        }
    }

    // MARK: - Configuration Defaults

    object Defaults {
        // Network
        const val REQUEST_TIMEOUT_MS = 30000L // 30 seconds
        const val CONNECT_TIMEOUT_MS = 15000L // 15 seconds
        const val READ_TIMEOUT_MS = 30000L // 30 seconds
        const val RETRY_ATTEMPTS = 3
        const val RETRY_DELAY_MS = 1000L // 1 second

        // Database
        const val DATABASE_NAME = "runanywhere.db"
        const val DATABASE_VERSION = 1

        // Telemetry
        const val TELEMETRY_BATCH_SIZE = 50
        const val TELEMETRY_UPLOAD_INTERVAL_MS = 300000L // 5 minutes
        const val TELEMETRY_RETRY_ATTEMPTS = 3
        const val TELEMETRY_MAX_EVENTS = 1000

        // Model Management
        const val MAX_MODEL_SIZE_BYTES = 2000000000L // 2GB
        const val MODEL_DOWNLOAD_CHUNK_SIZE = 8192 // 8KB
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
        const val AUTH_TOKEN_REFRESH_THRESHOLD_SECONDS = 300L // 5 minutes before expiry
        const val MAX_AUTH_RETRY_ATTEMPTS = 3

        // Device Info
        const val DEVICE_INFO_UPDATE_INTERVAL_MS = 60000L // 1 minute
        const val MEMORY_PRESSURE_UPDATE_INTERVAL_MS = 5000L // 5 seconds
    }

    // MARK: - Storage Paths

    object Storage {
        // Base directories
        const val BASE_DIRECTORY = "runanywhere"
        const val MODELS_DIRECTORY = "$BASE_DIRECTORY/models"
        const val CACHE_DIRECTORY = "$BASE_DIRECTORY/cache"
        const val TEMP_DIRECTORY = "$BASE_DIRECTORY/temp"
        const val LOGS_DIRECTORY = "$BASE_DIRECTORY/logs"

        // Model subdirectories
        const val LANGUAGE_MODELS_DIR = "$MODELS_DIRECTORY/language"
        const val SPEECH_MODELS_DIR = "$MODELS_DIRECTORY/speech"
        const val VISION_MODELS_DIR = "$MODELS_DIRECTORY/vision"

        // Cache subdirectories
        const val NETWORK_CACHE_DIR = "$CACHE_DIRECTORY/network"
        const val MODEL_CACHE_DIR = "$CACHE_DIRECTORY/models"
        const val TELEMETRY_CACHE_DIR = "$CACHE_DIRECTORY/telemetry"
    }

    // MARK: - Secure Storage Keys

    object SecureStorage {
        const val KEYSTORE_ALIAS = "runanywhere_sdk_keystore"
        const val SHARED_PREFS_NAME = "runanywhere_secure_prefs"

        // Keys for encrypted storage
        const val ACCESS_TOKEN_KEY = "access_token"
        const val REFRESH_TOKEN_KEY = "refresh_token"
        const val API_KEY_KEY = "api_key"
        const val DEVICE_ID_KEY = "device_id"
        const val USER_PREFERENCES_KEY = "user_preferences"
    }

    // MARK: - Development Mode

    object Development {
        val MOCK_DELAY_MS = if (ENVIRONMENT == Environment.DEVELOPMENT) 500L else 0L
        val ENABLE_VERBOSE_LOGGING = ENVIRONMENT == Environment.DEVELOPMENT
        val ENABLE_MOCK_SERVICES = ENVIRONMENT == Environment.DEVELOPMENT

        // Mock data generation
        const val MOCK_DEVICE_ID_PREFIX = "dev-device-"
        const val MOCK_SESSION_ID_PREFIX = "dev-session-"
        const val MOCK_USER_ID_PREFIX = "dev-user-"
    }

    // MARK: - Feature Flags

    object Features {
        // Core features
        val ENABLE_ON_DEVICE_INFERENCE = true
        val ENABLE_CLOUD_FALLBACK = true
        val ENABLE_TELEMETRY = true
        val ENABLE_ANALYTICS = true

        // Development features
        val ENABLE_DEBUG_LOGGING = ENVIRONMENT == Environment.DEVELOPMENT
        val ENABLE_PERFORMANCE_MONITORING = true
        val ENABLE_CRASH_REPORTING = ENVIRONMENT == Environment.PRODUCTION

        // STT features
        val ENABLE_VAD = true
        val ENABLE_STT_ANALYTICS = true
        val ENABLE_REAL_TIME_STT = true
        val ENABLE_STT_CONFIDENCE_SCORING = true
    }

    // MARK: - Error Codes

    object ErrorCodes {
        // Network errors
        const val NETWORK_UNAVAILABLE = 1001
        const val REQUEST_TIMEOUT = 1002
        const val AUTHENTICATION_FAILED = 1003
        const val INVALID_API_KEY = 1004

        // Model errors
        const val MODEL_NOT_FOUND = 2001
        const val MODEL_DOWNLOAD_FAILED = 2002
        const val MODEL_LOAD_FAILED = 2003
        const val INSUFFICIENT_MEMORY = 2004

        // STT errors
        const val STT_INITIALIZATION_FAILED = 3001
        const val STT_PROCESSING_FAILED = 3002
        const val AUDIO_RECORDING_FAILED = 3003
        const val VAD_INITIALIZATION_FAILED = 3004

        // General errors
        const val INITIALIZATION_FAILED = 5001
        const val CONFIGURATION_INVALID = 5002
        const val PERMISSION_DENIED = 5003
        const val STORAGE_UNAVAILABLE = 5004
    }
}
