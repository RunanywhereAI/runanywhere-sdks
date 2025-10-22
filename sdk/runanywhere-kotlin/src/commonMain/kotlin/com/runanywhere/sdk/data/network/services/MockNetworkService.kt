package com.runanywhere.sdk.data.network.services

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.network.NetworkService
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Mock network service for development mode
 * Returns predefined JSON responses without making actual network calls
 * Equivalent to iOS MockNetworkService
 * Enhanced to support generic type methods
 */
class MockNetworkService : NetworkService {

    private val logger = SDKLogger("MockNetworkService")
    private val mockDelay = 500L // 0.5 seconds to simulate network delay

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    init {
        logger.info("MockNetworkService initialized - all network calls will return mock data")
    }

    /**
     * POST request with JSON payload and typed response
     * Note: This implementation requires extension functions with reified types for actual usage
     */
    override suspend fun <T : Any, R : Any> post(
        endpoint: APIEndpoint,
        payload: T,
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use postTyped extension function with reified types instead")
    }

    /**
     * GET request with typed response
     * Note: This implementation requires extension functions with reified types for actual usage
     */
    override suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use getTyped extension function with reified types instead")
    }

    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray {
        logger.debug("Mock POST to ${endpoint.url}")

        // Simulate network delay
        delay(mockDelay)

        // Return mock response based on endpoint
        return getMockResponse(endpoint, "POST")
    }

    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): ByteArray {
        logger.debug("Mock GET to ${endpoint.url}")

        // Simulate network delay
        delay(mockDelay)

        // Return mock response based on endpoint
        return getMockResponse(endpoint, "GET")
    }

    private fun getMockResponse(endpoint: APIEndpoint, method: String): ByteArray {
        logger.debug("Using programmatic mock data for ${endpoint.url}")
        return getProgrammaticMockData(endpoint, method)
    }

    private fun getProgrammaticMockData(endpoint: APIEndpoint, method: String): ByteArray {
        return when (endpoint) {
            APIEndpoint.authenticate -> {
                // Mock authentication response
                val response = mapOf(
                    "accessToken" to "mock-access-token-${System.currentTimeMillis()}",
                    "refreshToken" to "mock-refresh-token-${System.currentTimeMillis()}",
                    "expiresIn" to 3600,
                    "tokenType" to "Bearer"
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.refreshToken -> {
                // Mock refresh token response
                val response = mapOf(
                    "accessToken" to "mock-new-access-token-${System.currentTimeMillis()}",
                    "refreshToken" to "mock-new-refresh-token-${System.currentTimeMillis()}",
                    "expiresIn" to 3600,
                    "tokenType" to "Bearer"
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.healthCheck -> {
                // Mock health check response
                val response = mapOf(
                    "status" to "healthy",
                    "version" to "0.1.0",
                    "timestamp" to SimpleInstant.now().toEpochMilliseconds()
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.registerDevice -> {
                // Mock device registration response
                val response = mapOf(
                    "deviceId" to "mock-device-${System.currentTimeMillis()}",
                    "registered" to true,
                    "message" to "Device registered successfully"
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.deviceInfo -> {
                // Mock device info update response
                val response = mapOf(
                    "deviceId" to "mock-device-${System.currentTimeMillis()}",
                    "updated" to true,
                    "message" to "Device information updated successfully"
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.configuration -> {
                // Mock configuration response - use the default configuration
                val config = ConfigurationData.defaultConfiguration("dev-mode")
                json.encodeToString(config).toByteArray()
            }

            APIEndpoint.models -> {
                // Return mock models for development mode
                val models = createMockModels()
                json.encodeToString(models).toByteArray()
            }

            APIEndpoint.telemetry -> {
                // Return simple success response
                val response = mapOf(
                    "success" to true,
                    "message" to "Telemetry received"
                )
                json.encodeToString(response).toByteArray()
            }

            APIEndpoint.history -> {
                // Return empty array for generation history
                val emptyHistory: List<String> = emptyList()
                json.encodeToString(emptyHistory).toByteArray()
            }

            APIEndpoint.preferences -> {
                // Return basic preferences
                val preferences = mapOf(
                    "preferOnDevice" to true,
                    "maxCostPerRequest" to 0.01,
                    "preferredModels" to emptyList<String>()
                )
                json.encodeToString(preferences).toByteArray()
            }
        }
    }

    /**
     * Create mock models with real downloadable URLs
     * These are actual GGML models that can be downloaded and used
     */
    private fun createMockModels(): List<ModelInfo> {
        return listOf(
            // Whisper Base - Real GGML model for JVM/Android
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                localPath = null,
                downloadSize = 74_000_000L, // ~74MB
                memoryRequired = 74_000_000L, // 74MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            ),

            // Whisper Tiny - Smaller model for faster testing
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                localPath = null,
                downloadSize = 39_000_000L, // ~39MB
                memoryRequired = 39_000_000L, // 39MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            )
        )
    }
}
