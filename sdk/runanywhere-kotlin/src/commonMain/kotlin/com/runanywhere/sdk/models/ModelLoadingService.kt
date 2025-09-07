package com.runanywhere.sdk.models

import com.runanywhere.sdk.data.models.LoadedModel
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.download.DownloadService
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Model loading service with download support
 */
class ModelLoadingService(
    private val modelRegistry: ModelRegistry,
    private val downloadService: DownloadService
) {
    private val logger = SDKLogger("ModelLoadingService")
    private val loadedModels = mutableMapOf<String, LoadedModel>()

    suspend fun loadModel(modelId: String): LoadedModel = withContext(Dispatchers.Default) {
        logger.info("Loading model: $modelId")

        // Check if already loaded
        loadedModels[modelId]?.let {
            logger.info("Model $modelId already loaded")
            return@withContext it
        }

        // Get model info from registry
        val modelInfo = modelRegistry.getModel(modelId)
            ?: throw SDKError.ModelNotFound(modelId)

        // Check if model file exists locally
        val modelPath = FileManager.shared.getModelPath(modelId)
        val modelExists = FileManager.shared.fileExists(modelPath)

        if (!modelExists) {
            logger.info("Model $modelId not found locally, downloading...")

            // Emit download required event
            EventBus.publish(SDKModelEvent.DownloadStarted(modelId))

            try {
                // Download the model
                downloadModel(modelInfo, modelPath)

                // Emit download completed
                EventBus.publish(SDKModelEvent.DownloadCompleted(modelId))

            } catch (e: Exception) {
                logger.error("Failed to download model $modelId", e)
                EventBus.publish(SDKModelEvent.LoadFailed(modelId, e))
                throw SDKError.LoadingFailed("Failed to download model: ${e.message}")
            }
        } else {
            logger.info("Model $modelId found locally at $modelPath")
        }

        // Validate the model file exists
        val fileExists = FileManager.shared.fileExists(modelPath)
        if (!fileExists) {
            logger.error("Model $modelId file not found after download")
            throw SDKError.LoadingFailed("Model file not found, please try again")
        }

        // TODO: Add proper validation once ValidationService is platform-specific
        logger.info("Model $modelId validation skipped (development mode)")

        // Create LoadedModel instance
        val loadedModel = LoadedModel(
            model = modelInfo,
            localPath = modelPath,
            loadedAt = getCurrentTimeMillis()
        )

        // Cache the loaded model
        loadedModels[modelId] = loadedModel

        logger.info("Model $modelId loaded successfully")
        return@withContext loadedModel
    }

    private suspend fun downloadModel(modelInfo: ModelInfo, targetPath: String) {
        if (modelInfo.downloadURL == null) {
            throw SDKError.LoadingFailed("No download URL available for model ${modelInfo.id}")
        }

        // For development mode, we'll simulate a successful download
        // In production, this would actually download the model
        logger.info("Downloading model to $targetPath")

        // Create parent directories if needed
        val parentDir = targetPath.substringBeforeLast("/")
        FileManager.shared.createDirectory(parentDir)

        // For development, create a dummy file
        // In production, this would be replaced with actual download logic
        if (!FileManager.shared.fileExists(targetPath)) {
            // Write some dummy data to simulate a model file
            FileManager.shared.writeFile(
                targetPath,
                "DUMMY_MODEL_DATA_${modelInfo.id}".toByteArray()
            )
        }

        // Emit progress events
        for (progress in 1..10) {
            EventBus.publish(SDKModelEvent.DownloadProgress(modelInfo.id, progress / 10f))
            kotlinx.coroutines.delay(100) // Simulate download time
        }
    }

    fun isModelLoaded(modelId: String): Boolean {
        return loadedModels.containsKey(modelId)
    }

    fun getLoadedModel(modelId: String): LoadedModel? {
        return loadedModels[modelId]
    }

    fun unloadModel(modelId: String) {
        loadedModels.remove(modelId)
        logger.info("Model $modelId unloaded")
    }

    fun clearAllModels() {
        loadedModels.clear()
        logger.info("All models unloaded")
    }
}
