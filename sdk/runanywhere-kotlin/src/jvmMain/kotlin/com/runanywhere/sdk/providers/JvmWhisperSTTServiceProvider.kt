package com.runanywhere.sdk.providers

import com.runanywhere.sdk.components.stt.JvmWhisperSTTService
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.JvmWhisperJNIModelMapper
import com.runanywhere.sdk.models.JvmModelStorage

/**
 * JVM WhisperJNI STT Service Provider
 *
 * This provider creates JvmWhisperSTTService instances that use the
 * io.github.givimad:whisper-jni library for actual speech-to-text transcription.
 *
 * Replaces the mock implementation with real WhisperJNI functionality.
 */
class JvmWhisperSTTServiceProvider : STTServiceProvider {
    private val logger = SDKLogger("JvmWhisperSTTServiceProvider")
    private val modelStorage = JvmModelStorage()

    companion object {
        /**
         * Register this provider with the module registry.
         * This replaces any existing WhisperKit providers with the real JVM implementation.
         */
        fun register() {
            val provider = JvmWhisperSTTServiceProvider()
            ModuleRegistry.registerSTT(provider)
        }
    }

    override val name: String = "WhisperJNI-JVM"

    override fun canHandle(modelId: String?): Boolean {
        // This provider can handle:
        // 1. No specific model (use default)
        // 2. Any Whisper model ID
        // 3. Common size identifiers
        return modelId == null ||
               JvmWhisperJNIModelMapper.isModelSupported(modelId) ||
               isWhisperCompatibleModelId(modelId)
    }

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        logger.info("Creating JvmWhisperSTTService with configuration: ${configuration.modelId}")

        return try {
            val service = JvmWhisperSTTService()

            // Check if model is available, download if needed
            val modelId = configuration.modelId ?: "whisper-base"
            if (!modelStorage.isModelAvailable(modelId)) {
                logger.info("Model $modelId not found locally, downloading...")

                // Download the model
                modelStorage.downloadModel(modelId).collect { progress ->
                    logger.info("Download progress for $modelId: ${(progress * 100).toInt()}%")
                }
            }

            // Initialize the service with the model
            service.initialize(configuration.modelId)

            logger.info("JvmWhisperSTTService created and initialized successfully")
            service

        } catch (e: Exception) {
            logger.error("Failed to create JvmWhisperSTTService", e)
            throw e
        }
    }

    /**
     * Check if model ID is compatible with Whisper models
     */
    private fun isWhisperCompatibleModelId(modelId: String): Boolean {
        val lowerModelId = modelId.lowercase()

        return lowerModelId.contains("whisper") ||
               lowerModelId in setOf(
                   "tiny", "base", "small", "medium", "large",
                   "smallest", "default", "largest",
                   "large-v2", "large-v3"
               )
    }

    /**
     * Get information about available models
     */
    fun getAvailableModels() = modelStorage.getAllAvailableModels()

    /**
     * Get storage statistics
     */
    fun getStorageStats() = modelStorage.getStorageStats()

    /**
     * Clean up model storage (remove temporary files, validate models)
     */
    fun cleanupStorage() = modelStorage.cleanup()
}
