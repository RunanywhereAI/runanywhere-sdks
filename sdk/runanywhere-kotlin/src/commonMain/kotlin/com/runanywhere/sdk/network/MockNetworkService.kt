package com.runanywhere.sdk.network

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.QuantizationLevel
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.services.download.NetworkService
import com.runanywhere.sdk.utils.SDKConstants
import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Mock network service for development mode - exact match with iOS MockNetworkService
 * Returns predefined model responses without making actual network calls
 */
class MockNetworkService : NetworkService {

    private val logger = SDKLogger("MockNetworkService")

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

    /**
     * Mock download implementation with simulated progress
     * Matches iOS MockNetworkService download behavior
     */
    override suspend fun downloadFile(
        url: String,
        destinationPath: String,
        progressCallback: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?
    ) {
        logger.info("Mock download from: $url to: $destinationPath")

        // Simulate network delay
        delay(mockDelay)

        // Find mock model by URL to get size
        val mockModel = createMockModels().find { it.downloadURL == url }
        val totalBytes = mockModel?.downloadSize ?: 100_000_000L // Default 100MB

        // Simulate download progress in chunks
        val chunks = 20 // Download in 20 chunks
        val chunkSize = totalBytes / chunks

        for (i in 1..chunks) {
            delay(100) // Simulate chunk download time

            val bytesDownloaded = (chunkSize * i).coerceAtMost(totalBytes)
            progressCallback?.invoke(bytesDownloaded, totalBytes)

            logger.debug("Mock download progress: ${(bytesDownloaded * 100 / totalBytes)}%")
        }

        logger.info("Mock download completed: $destinationPath")
    }

    /**
     * Create comprehensive mock models matching iOS exactly
     */
    fun createComprehensiveMockModels(): List<ModelInfo> {
        return listOf(
            // Apple Foundation Models (iOS 18+ built-in)
            ModelInfo(
                id = "foundation-models-default",
                name = "Apple Foundation Models",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.MLMODEL,
                downloadURL = null, // Built-in, no download
                localPath = null,
                downloadSize = 0,
                memoryRequired = 0,
                compatibleFrameworks = listOf(LLMFramework.FOUNDATION_MODELS),
                preferredFramework = LLMFramework.FOUNDATION_MODELS,
                contextLength = 8192,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            ),

            // Llama models
            ModelInfo(
                id = "llama-3.2-1b-instruct-q6-k",
                name = "Llama 3.2 1B Instruct (Q6_K)",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                localPath = null,
                downloadSize = 1_100_000_000, // ~1.1GB
                memoryRequired = 2_000_000_000, // ~2GB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 131072,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            ),

            // Whisper models - comprehensive set
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                localPath = null,
                downloadSize = 39_000_000, // 39MB
                memoryRequired = 100_000_000, // 100MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            ),

            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                localPath = null,
                downloadSize = 74_000_000, // 74MB
                memoryRequired = 200_000_000, // 200MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            ),

            ModelInfo(
                id = "whisper-small",
                name = "Whisper Small",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
                localPath = null,
                downloadSize = 244_000_000, // 244MB
                memoryRequired = 500_000_000, // 500MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            )
        )
    }

    private fun createMockModels(): List<ModelInfo> {
        // Return simple set for basic usage, or comprehensive set based on config
        return if (SDKConstants.Development.USE_COMPREHENSIVE_MOCKS) {
            createComprehensiveMockModels()
        } else {
            // Only include Whisper Base model as default
            listOf(
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
                    supportsThinking = false,
                    createdAt = SimpleInstant.now(),
                    updatedAt = SimpleInstant.now()
                )
            )
        }
    }
}
