package com.runanywhere.sdk.whisper

import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.models.enums.LLMFramework

/**
 * Whisper STT service provider implementation
 * Provides on-device speech-to-text using whisper.cpp
 */
class WhisperSTTProvider : STTServiceProvider {

    private val logger = SDKLogger("WhisperSTTProvider")

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        val modelId = configuration.modelId ?: "whisper-base"
        logger.info("Creating Whisper STT service with model: $modelId")

        // For development mode with hardcoded models, handle model downloading
        val modelPath = if (modelId == "whisper-base" || modelId == "whisper-tiny") {
            // Get the model from available models
            val modelInfo = ServiceContainer.shared.modelInfoService?.getAvailableModels()
                ?.firstOrNull { it.id == modelId }

            if (modelInfo != null && modelInfo.downloadURL != null) {
                logger.info("Found model info for $modelId, ensuring model is downloaded")

                try {
                    // Download model if needed
                    val path = ServiceContainer.shared.modelManager?.ensureModel(modelInfo)
                    logger.info("Model available at: $path")
                    path
                } catch (e: Exception) {
                    logger.error("Failed to download model: ${e.message}", e)
                    // Fall back to mock mode
                    modelId
                }
            } else {
                logger.info("No download URL for model $modelId, using mock mode")
                modelId
            }
        } else {
            // For custom model paths, use as-is
            modelId
        }

        val service = WhisperSTTServiceImpl()
        service.initialize(modelPath)
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
