package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.QuantizationLevel
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SDKConstants
import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Mock implementation of NetworkService for development mode
 * Matches iOS MockNetworkService - returns predefined responses without making actual network calls
 */
class MockNetworkService : NetworkService {

    private val logger = SDKLogger("MockNetworkService")
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    /**
     * Simulated network delay in milliseconds
     */
    private val mockDelay = SDKConstants.Development.MOCK_DELAY_MS

    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray {
        // Simulate network delay
        delay(mockDelay)

        logger.debug("Mock POST to ${endpoint.url}")

        // Return mock response based on endpoint
        return when (endpoint) {
            APIEndpoint.MODELS -> getMockModelsResponse()
            APIEndpoint.CONFIGURATION -> getMockConfigurationResponse()
            APIEndpoint.TELEMETRY -> ByteArray(0) // Empty response for telemetry
            APIEndpoint.HEALTH_CHECK -> getMockStatusResponse()
            else -> ByteArray(0)
        }
    }

    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): ByteArray {
        // Simulate network delay
        delay(mockDelay)

        logger.debug("Mock GET to ${endpoint.url}")

        // Return mock response based on endpoint
        return when (endpoint) {
            APIEndpoint.MODELS -> getMockModelsResponse()
            APIEndpoint.CONFIGURATION -> getMockConfigurationResponse()
            APIEndpoint.HEALTH_CHECK -> getMockStatusResponse()
            APIEndpoint.DEVICE_INFO -> getMockDeviceInfoResponse()
            else -> ByteArray(0)
        }
    }

    /**
     * Get mock models response - comprehensive list matching iOS
     */
    private fun getMockModelsResponse(): ByteArray {
        val models = createComprehensiveMockModels()
        val response = mapOf(
            "models" to models,
            "timestamp" to SimpleInstant.now().toEpochMilliseconds()
        )
        return json.encodeToString(response).encodeToByteArray()
    }

    /**
     * Get mock device info response
     */
    private fun getMockDeviceInfoResponse(): ByteArray {
        val deviceInfo = mapOf(
            "deviceId" to "mock-device-id",
            "platform" to "KMP",
            "osVersion" to "1.0.0",
            "appVersion" to "1.0.0"
        )
        return json.encodeToString(deviceInfo).encodeToByteArray()
    }

    /**
     * Get mock configuration response
     */
    private fun getMockConfigurationResponse(): ByteArray {
        val config = mapOf(
            "version" to "1.0.0",
            "minSdkVersion" to "1.0.0",
            "features" to mapOf(
                "stt" to true,
                "tts" to true,
                "llm" to true,
                "vad" to true
            ),
            "endpoints" to mapOf(
                "api" to "https://api.runanywhere.ai",
                "cdn" to "https://cdn.runanywhere.ai"
            )
        )
        return json.encodeToString(config).encodeToByteArray()
    }

    /**
     * Get mock status response
     */
    private fun getMockStatusResponse(): ByteArray {
        val status = mapOf(
            "status" to "healthy",
            "version" to "1.0.0",
            "timestamp" to SimpleInstant.now().toEpochMilliseconds()
        )
        return json.encodeToString(status).encodeToByteArray()
    }

    /**
     * Create comprehensive mock models matching iOS implementation
     * This method is also available for other components to use directly
     */
    fun createComprehensiveMockModels(): List<ModelInfo> {
        val models = mutableListOf<ModelInfo>()

        // Whisper Models (Speech Recognition)
        models.addAll(createWhisperModels())

        // LLM Models
        models.addAll(createLLMModels())

        // TTS Models
        models.addAll(createTTSModels())

        return models
    }

    private fun createWhisperModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-tiny",
                downloadSize = 39_000_000L,
                memoryRequired = 100_000_000L,
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_KIT,
                metadata = ModelInfoMetadata(
                    description = "Smallest and fastest Whisper model",
                    version = "1.0.0",
                    quantizationLevel = QuantizationLevel.F16
                ),
                source = ConfigurationSource.REMOTE
            ),
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-base",
                downloadSize = 74_000_000L,
                memoryRequired = 200_000_000L,
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_KIT,
                metadata = ModelInfoMetadata(
                    description = "Good balance between speed and accuracy",
                    version = "1.0.0",
                    quantizationLevel = QuantizationLevel.F16
                ),
                source = ConfigurationSource.REMOTE
            ),
            ModelInfo(
                id = "whisper-small",
                name = "Whisper Small",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-small",
                downloadSize = 244_000_000L,
                memoryRequired = 500_000_000L,
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_KIT,
                metadata = ModelInfoMetadata(
                    description = "Better accuracy with reasonable performance",
                    version = "1.0.0",
                    quantizationLevel = QuantizationLevel.F16
                ),
                source = ConfigurationSource.REMOTE
            )
        )
    }

    private fun createLLMModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "llama-3.2-1b",
                name = "Llama 3.2 1B",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.gguf",
                downloadSize = 750_000_000L,
                memoryRequired = 2_000_000_000L,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP, LLMFramework.MLX),
                preferredFramework = LLMFramework.LLAMA_CPP,
                metadata = ModelInfoMetadata(
                    description = "Small but capable language model",
                    version = "3.2",
                    quantizationLevel = QuantizationLevel.Q4_K_M
                ),
                source = ConfigurationSource.REMOTE
            ),
            ModelInfo(
                id = "llama-3.2-3b",
                name = "Llama 3.2 3B",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit/resolve/main/model.gguf",
                downloadSize = 2_000_000_000L,
                memoryRequired = 4_000_000_000L,
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP, LLMFramework.MLX),
                preferredFramework = LLMFramework.LLAMA_CPP,
                metadata = ModelInfoMetadata(
                    description = "Balanced performance and capability",
                    version = "3.2",
                    quantizationLevel = QuantizationLevel.Q4_K_M
                ),
                source = ConfigurationSource.REMOTE
            )
        )
    }

    private fun createTTSModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "piper-en-us",
                name = "Piper English US",
                category = ModelCategory.SPEECH_SYNTHESIS,
                format = ModelFormat.ONNX,
                downloadURL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/model.onnx",
                downloadSize = 63_000_000L,
                memoryRequired = 150_000_000L,
                compatibleFrameworks = listOf(LLMFramework.ONNX),
                preferredFramework = LLMFramework.ONNX,
                metadata = ModelInfoMetadata(
                    description = "Natural English voice synthesis",
                    version = "1.0.0",
                    quantizationLevel = QuantizationLevel.F32
                ),
                source = ConfigurationSource.REMOTE
            )
        )
    }
}
