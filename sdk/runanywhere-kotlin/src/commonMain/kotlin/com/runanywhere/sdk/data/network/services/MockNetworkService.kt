package com.runanywhere.sdk.data.network.services

import android.util.Log
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.data.network.NetworkService
import com.runanywhere.sdk.utils.JsonUtils
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

/**
 * Mock network service for development mode
 * Returns predefined JSON responses without making actual network calls
 * Exact translation from iOS MockNetworkService.swift
 */
class MockNetworkService : NetworkService {

    companion object {
        private const val TAG = "MockNetworkService"
        private const val MOCK_DELAY = 500L // 0.5 seconds to simulate network delay
    }

    private val mutex = Mutex()
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    init {
        Log.i(TAG, "MockNetworkService initialized - all network calls will return mock data")
    }

    // MARK: - NetworkService Protocol

    override suspend fun postRaw(endpoint: APIEndpoint, payload: ByteArray, requiresAuth: Boolean): ByteArray = mutex.withLock {
        Log.d(TAG, "Mock POST to ${endpoint.path}")

        // Simulate network delay
        delay(MOCK_DELAY)

        // Return mock response based on endpoint
        return@withLock getMockResponse(endpoint, "POST")
    }

    override suspend fun getRaw(endpoint: APIEndpoint, requiresAuth: Boolean): ByteArray = mutex.withLock {
        Log.d(TAG, "Mock GET to ${endpoint.path}")

        // Simulate network delay
        delay(MOCK_DELAY)

        // Return mock response based on endpoint
        return@withLock getMockResponse(endpoint, "GET")
    }

    // MARK: - Mock Data Management

    private fun getMockResponse(endpoint: APIEndpoint, method: String): ByteArray {
        // First try to load from JSON file if available
        loadMockFile(endpoint, method)?.let { fileData ->
            Log.d(TAG, "Loaded mock data from file for ${endpoint.path}")
            return fileData
        }

        // Otherwise return programmatic mock data
        Log.d(TAG, "Using programmatic mock data for ${endpoint.path}")
        return getProgrammaticMockData(endpoint, method)
    }

    private fun loadMockFile(endpoint: APIEndpoint, method: String): ByteArray? {
        // Build file name from endpoint path
        val fileName = buildMockFileName(endpoint, method)

        // Try to load from assets (Android equivalent of Bundle.main)
        return try {
            // This would require context for assets access - for now return null
            // In a real implementation, you would inject Context and access assets
            null
        } catch (e: Exception) {
            Log.w(TAG, "Could not load mock file: $fileName", e)
            null
        }
    }

    private fun buildMockFileName(endpoint: APIEndpoint, method: String): String {
        // Convert endpoint path to file name
        // e.g., /v1/auth/token with POST -> post_v1_auth_token
        val cleanPath = endpoint.path
            .replace("/", "_")
            .trim('_')

        return "${method.lowercase()}_$cleanPath"
    }

    private fun getProgrammaticMockData(endpoint: APIEndpoint, method: String): ByteArray {
        return when (endpoint) {
            is APIEndpoint.Authenticate -> {
                val response = AuthenticationResponse(
                    accessToken = "mock-access-token-${UUID.randomUUID()}",
                    refreshToken = "mock-refresh-token-${UUID.randomUUID()}",
                    expiresIn = 3600,
                    tokenType = "Bearer"
                )
                json.encodeToString(response).toByteArray()
            }

            is APIEndpoint.HealthCheck -> {
                val response = HealthCheckResponse(
                    status = HealthStatus.HEALTHY,
                    version = SDKConstants.VERSION,
                    timestamp = Clock.System.now().toEpochMilliseconds()
                )
                json.encodeToString(response).toByteArray()
            }

            is APIEndpoint.Configuration -> {
                val config = ConfigurationData(
                    id = "mock-config-${UUID.randomUUID()}",
                    apiKey = "dev-mode",
                    source = ConfigurationSource.REMOTE,
                    routing = RoutingConfiguration(
                        preferOnDevice = true,
                        costThreshold = CostThreshold(maxCostPerRequest = 0.01),
                        fallbackBehavior = FallbackBehavior.CLOUD_FALLBACK,
                        deviceCapabilityThreshold = DeviceCapabilityThreshold(
                            minimumMemoryMB = 1000,
                            minimumStorageMB = 500,
                            requiresNeuralEngine = false,
                            maxBatteryUsage = 0.3f
                        )
                    ),
                    models = ModelConfiguration(
                        preferredModels = emptyList(),
                        maxModelSize = 2000000000L, // 2GB
                        autoDownload = true,
                        downloadOnWifiOnly = true
                    ),
                    telemetry = TelemetryConfiguration(
                        enableTelemetry = true,
                        batchSize = 50,
                        uploadInterval = 300000L, // 5 minutes
                        retryAttempts = 3
                    ),
                    privacy = PrivacyConfiguration(
                        dataCollection = DataCollectionLevel.ESSENTIAL,
                        anonymizeData = true,
                        retentionPeriod = 86400000L * 30 // 30 days
                    ),
                    createdAt = Clock.System.now().toEpochMilliseconds(),
                    updatedAt = Clock.System.now().toEpochMilliseconds()
                )
                json.encodeToString(config).toByteArray()
            }

            is APIEndpoint.Models -> {
                // Return mock models for development mode
                val models = createMockModels()
                json.encodeToString(models).toByteArray()
            }

            is APIEndpoint.DeviceInfo -> {
                val deviceInfo = DeviceInfoData(
                    deviceId = "mock-device-${UUID.randomUUID()}",
                    model = "Android Device",
                    osVersion = "Android 14",
                    architecture = "arm64-v8a",
                    totalMemoryMB = 8000,
                    availableMemoryMB = 4000,
                    totalStorageMB = 128000,
                    availableStorageMB = 64000,
                    hasNeuralEngine = true,
                    gpuType = GPUType.ADRENO,
                    cpuCores = 8,
                    batteryLevel = 0.75f,
                    isCharging = false,
                    thermalState = ThermalState.NOMINAL,
                    memoryPressure = 0.3f,
                    createdAt = Clock.System.now().toEpochMilliseconds(),
                    updatedAt = Clock.System.now().toEpochMilliseconds()
                )
                json.encodeToString(deviceInfo).toByteArray()
            }

            is APIEndpoint.Telemetry -> {
                // Return simple success response
                val response = mapOf("success" to true, "message" to "Telemetry received")
                json.encodeToString(response).toByteArray()
            }

            is APIEndpoint.GenerationHistory -> {
                // Return empty array for generation history
                val emptyHistory = emptyList<String>()
                json.encodeToString(emptyHistory).toByteArray()
            }

            is APIEndpoint.UserPreferences -> {
                // Return basic preferences as dictionary
                val preferences = mapOf(
                    "preferOnDevice" to true,
                    "maxCostPerRequest" to 0.01,
                    "preferredModels" to emptyList<String>()
                )
                json.encodeToString(preferences).toByteArray()
            }
        }
    }

    private fun createMockModels(): List<ModelInfoData> {
        return listOf(
            // Llama-3.2 1B Q6_K
            ModelInfoData(
                id = "llama-3.2-1b-instruct-q6-k",
                name = "Llama 3.2 1B Instruct Q6_K",
                description = "Meta's Llama 3.2 1B parameter model with Q6_K quantization",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                localPath = null,
                downloadSize = 1100000000L, // ~1.1GB
                memoryRequired = 1200000000L, // 1.2GB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 131072,
                supportsThinking = true,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // SmolLM2 1.7B Instruct Q6_K_L
            ModelInfoData(
                id = "smollm2-1.7b-instruct-q6-k-l",
                name = "SmolLM2 1.7B Instruct Q6_K_L",
                description = "HuggingFace SmolLM2 1.7B parameter instruction-tuned model",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
                localPath = null,
                downloadSize = 1700000000L, // ~1.7GB
                memoryRequired = 1800000000L, // 1.8GB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 8192,
                supportsThinking = true,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // Qwen-2.5 0.5B Q6_K
            ModelInfoData(
                id = "qwen-2.5-0.5b-instruct-q6-k",
                name = "Qwen 2.5 0.5B Instruct Q6_K",
                description = "Alibaba Qwen 2.5 0.5B parameter instruction-tuned model",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                localPath = null,
                downloadSize = 650000000L, // ~650MB
                memoryRequired = 600000000L, // 600MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = true,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // SmolLM2 360M Q8_0
            ModelInfoData(
                id = "smollm2-360m-q8-0",
                name = "SmolLM2 360M Q8_0",
                description = "HuggingFace SmolLM2 360M parameter model with Q8_0 quantization",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                localPath = null,
                downloadSize = 385000000L, // ~385MB
                memoryRequired = 500000000L, // 500MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 8192,
                supportsThinking = false,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // Qwen-2.5 1.5B Q6_K
            ModelInfoData(
                id = "qwen-2.5-1.5b-instruct-q6-k",
                name = "Qwen 2.5 1.5B Instruct Q6_K",
                description = "Alibaba Qwen 2.5 1.5B parameter instruction-tuned model",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
                localPath = null,
                downloadSize = 1400000000L, // ~1.4GB
                memoryRequired = 1600000000L, // 1.6GB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = true,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // MARK: - Voice Models (Whisper)

            // Whisper Tiny
            ModelInfoData(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                description = "OpenAI Whisper tiny model for speech recognition",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.ONNX,
                downloadURL = "https://huggingface.co/openai/whisper-tiny/resolve/main/pytorch_model.bin",
                localPath = null,
                downloadSize = 39000000L, // ~39MB
                memoryRequired = 39000000L, // 39MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.WHISPER_JNI),
                preferredFramework = LLMFramework.WHISPER_JNI,
                contextLength = 0,
                supportsThinking = false,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // Whisper Base
            ModelInfoData(
                id = "whisper-base",
                name = "Whisper Base",
                description = "OpenAI Whisper base model for speech recognition",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.ONNX,
                downloadURL = "https://huggingface.co/openai/whisper-base/resolve/main/pytorch_model.bin",
                localPath = null,
                downloadSize = 74000000L, // ~74MB
                memoryRequired = 74000000L, // 74MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.WHISPER_JNI),
                preferredFramework = LLMFramework.WHISPER_JNI,
                contextLength = 0,
                supportsThinking = false,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // MARK: - LiquidAI Models

            // LiquidAI LFM2 350M Q4_K_M (Smallest, fastest)
            ModelInfoData(
                id = "lfm2-350m-q4-k-m",
                name = "LiquidAI LFM2 350M Q4_K_M",
                description = "LiquidAI Liquid Foundation Model 2 350M parameters - fastest option",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                localPath = null,
                downloadSize = 218690000L, // ~219MB
                memoryRequired = 250000000L, // 250MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = false,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            ),

            // LiquidAI LFM2 350M Q8_0 (Highest quality)
            ModelInfoData(
                id = "lfm2-350m-q8-0",
                name = "LiquidAI LFM2 350M Q8_0",
                description = "LiquidAI Liquid Foundation Model 2 350M parameters - highest quality",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                localPath = null,
                downloadSize = 361650000L, // ~362MB
                memoryRequired = 400000000L, // 400MB
                isDownloaded = false,
                isBuiltIn = false,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = false,
                downloadProgress = 0.0f,
                lastUsed = null,
                createdAt = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            )
        )
    }
}
