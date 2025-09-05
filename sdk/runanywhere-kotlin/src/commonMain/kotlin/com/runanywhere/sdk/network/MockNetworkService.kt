package com.runanywhere.sdk.network

import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.QuantizationLevel
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.delay

/**
 * Mock network service for development mode - exact match with iOS MockNetworkService
 * Returns predefined model responses without making actual network calls
 */
class MockNetworkService {

    /**
     * Simulated network delay in milliseconds
     */
    private val mockDelay = SDKConstants.Development.MOCK_DELAY_MS

    /**
     * Get mock models for development - exact same models as iOS
     */
    suspend fun fetchModels(): List<ModelInfo> {
        // Simulate network delay
        delay(mockDelay)

        return createMockModels()
    }

    private fun createMockModels(): List<ModelInfo> {
        // Only include Whisper Base model as default
        return listOf(
            // Whisper Base - Default model
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                // Use hardcoded URL for development mode
                downloadURL = SDKConstants.ModelUrls.WHISPER_BASE.takeIf { it.isNotEmpty() }
                    ?: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                localPath = null,
                downloadSize = 74_000_000, // ~74MB
                memoryRequired = 74_000_000, // 74MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false
            )
        )
    }
}
