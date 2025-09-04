package com.runanywhere.sdk.network

import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.QuantizationLevel
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.delay

/**
 * Mock network service for development mode - exact match with iOS MockNetworkService
 * Returns predefined model responses without making actual network calls
 */
class MockNetworkService {

    /**
     * Simulated network delay in milliseconds
     */
    private val mockDelay = 500L

    /**
     * Get mock models for development - exact same models as iOS
     */
    suspend fun fetchModels(): List<ModelInfo> {
        // Simulate network delay
        delay(mockDelay)

        return createMockModels()
    }

    private fun createMockModels(): List<ModelInfo> {
        return listOf(
            // Apple Foundation Models (iOS 18+ equivalent for Android)
            ModelInfo(
                id = "foundation-models-default",
                name = "Apple Foundation Model",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.MLMODEL,
                downloadURL = null, // Built-in, no download needed
                localPath = null,
                downloadSize = 0, // Built-in
                memoryRequired = 500_000_000, // 500MB
                compatibleFrameworks = listOf(LLMFramework.FOUNDATION_MODELS),
                preferredFramework = LLMFramework.FOUNDATION_MODELS,
                contextLength = 8192,
                supportsThinking = false
            ),

            // Llama-3.2 1B Q6_K
            ModelInfo(
                id = "llama-3.2-1b-instruct-q6-k",
                name = "Llama 3.2 1B Instruct Q6_K",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                localPath = null,
                downloadSize = 1_100_000_000, // ~1.1GB
                memoryRequired = 1_200_000_000, // 1.2GB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 131072,
                supportsThinking = true
            ),

            // SmolLM2 1.7B Instruct Q6_K_L
            ModelInfo(
                id = "smollm2-1.7b-instruct-q6-k-l",
                name = "SmolLM2 1.7B Instruct Q6_K_L",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
                localPath = null,
                downloadSize = 1_700_000_000, // ~1.7GB
                memoryRequired = 1_800_000_000, // 1.8GB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 8192,
                supportsThinking = true
            ),

            // Qwen-2.5 0.5B Q6_K
            ModelInfo(
                id = "qwen-2.5-0.5b-instruct-q6-k",
                name = "Qwen 2.5 0.5B Instruct Q6_K",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                localPath = null,
                downloadSize = 650_000_000, // ~650MB
                memoryRequired = 600_000_000, // 600MB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = true
            ),

            // SmolLM2 360M Q8_0
            ModelInfo(
                id = "smollm2-360m-q8-0",
                name = "SmolLM2 360M Q8_0",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                localPath = null,
                downloadSize = 385_000_000, // ~385MB
                memoryRequired = 500_000_000, // 500MB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 8192,
                supportsThinking = false
            ),

            // Qwen-2.5 1.5B Q6_K
            ModelInfo(
                id = "qwen-2.5-1.5b-instruct-q6-k",
                name = "Qwen 2.5 1.5B Instruct Q6_K",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
                localPath = null,
                downloadSize = 1_400_000_000, // ~1.4GB
                memoryRequired = 1_600_000_000, // 1.6GB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = true
            ),

            // Voice Models (WhisperKit equivalents)

            // Whisper Tiny
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en",
                localPath = null,
                downloadSize = 39_000_000, // ~39MB
                memoryRequired = 39_000_000, // 39MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false
            ),

            // Whisper Base
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
                localPath = null,
                downloadSize = 74_000_000, // ~74MB
                memoryRequired = 74_000_000, // 74MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false
            ),

            // LiquidAI Models

            // LiquidAI LFM2 350M Q4_K_M (Smallest, fastest)
            ModelInfo(
                id = "lfm2-350m-q4-k-m",
                name = "LiquidAI LFM2 350M Q4_K_M",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                localPath = null,
                downloadSize = 218_690_000, // ~219MB
                memoryRequired = 250_000_000, // 250MB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = false
            ),

            // LiquidAI LFM2 350M Q8_0 (Highest quality)
            ModelInfo(
                id = "lfm2-350m-q8-0",
                name = "LiquidAI LFM2 350M Q8_0",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                localPath = null,
                downloadSize = 361_650_000, // ~362MB
                memoryRequired = 400_000_000, // 400MB
                compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
                preferredFramework = LLMFramework.LLAMA_CPP,
                contextLength = 32768,
                supportsThinking = false
            )
        )
    }
}
