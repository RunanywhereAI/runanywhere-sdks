package com.runanywhere.sdk.whisper

import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.STTConfiguration

/**
 * Whisper STT service provider implementation
 * Provides on-device speech-to-text using whisper.cpp
 */
class WhisperSTTProvider : STTServiceProvider {

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        val service = WhisperSTTServiceImpl()
        service.initialize(configuration.modelId)
        return service
    }

    override fun canHandle(modelId: String): Boolean {
        // Handle whisper models
        return modelId.contains("whisper") ||
               modelId.endsWith(".bin") ||
               modelId.contains("ggml")
    }

    override val name: String = "Whisper STT"

    override val priority: Int = 100 // High priority for on-device transcription

    override val supportedFeatures: Set<String> = setOf(
        "streaming",
        "timestamps",
        "translation",
        "language-detection",
        "multi-language",
        "gpu-acceleration"
    )
}
