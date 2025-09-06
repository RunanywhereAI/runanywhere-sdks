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
            // Whisper Base English - Compatible GGML model
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base English",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                // Use compatible English model
                downloadURL = SDKConstants.ModelUrls.WHISPER_BASE.takeIf { it.isNotEmpty() }
                    ?: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
                localPath = null,
                downloadSize = 141_000_000, // ~141MB - GGML format
                memoryRequired = 141_000_000, // 141MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            )
        )
    }
}
