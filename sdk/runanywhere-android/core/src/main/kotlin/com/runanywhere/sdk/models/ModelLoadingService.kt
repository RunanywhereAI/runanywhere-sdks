package com.runanywhere.sdk.models

import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.LoadedModel
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.DownloadService
import com.runanywhere.sdk.services.ValidationService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Model loading service with download support
 */
class ModelLoadingService(
    private val modelRegistry: ModelRegistry,
    private val downloadService: DownloadService,
    private val validationService: ValidationService
) {
    private val logger = SDKLogger("ModelLoadingService")
    private val loadedModels = mutableMapOf<String, LoadedModel>()

    suspend fun loadModel(modelId: String): LoadedModel = withContext(Dispatchers.IO) {
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
        val modelFile = FileManager.getModelPath(modelId)

        if (!modelFile.exists()) {
            logger.info("Model $modelId not found locally, downloading...")

            // Emit download required event
            EventBus.shared.publish(SDKModelEvent.DownloadStarted(modelId))

            try {
                // Download the model
                downloadModel(modelInfo, modelFile)

                // Emit download completed
                EventBus.shared.publish(SDKModelEvent.DownloadCompleted(modelId))

            } catch (e: Exception) {
                logger.error("Failed to download model $modelId", e)
                EventBus.shared.publish(SDKModelEvent.LoadFailed(modelId, e))
                throw SDKError.LoadingFailed("Failed to download model: ${e.message}")
            }
        } else {
            logger.info("Model $modelId found locally at ${modelFile.path}")
        }

        // Validate the model file
        val isValid = validationService.validate(modelFile.path, modelInfo)
        if (!isValid) {
            logger.error("Model $modelId validation failed")
            // Delete invalid model and try again
            modelFile.delete()
            throw SDKError.LoadingFailed("Model validation failed, please try again")
        }

        // Create LoadedModel instance
        val loadedModel = LoadedModel(
            model = modelInfo.copy(localPath = modelFile.path),
            localPath = modelFile.path,
            loadedAt = System.currentTimeMillis()
        )

        // Cache the loaded model
        loadedModels[modelId] = loadedModel

        logger.info("Model $modelId loaded successfully")
        return@withContext loadedModel
    }

    private suspend fun downloadModel(modelInfo: ModelInfo, targetFile: File) {
        if (modelInfo.downloadURL == null) {
            throw SDKError.LoadingFailed("No download URL available for model ${modelInfo.id}")
        }

        // For development mode, we'll simulate a successful download
        // In production, this would actually download the model
        logger.info("Simulating model download for development mode")

        // Create parent directories if needed
        targetFile.parentFile?.mkdirs()

        // For development, create a dummy file
        // In production, this would be replaced with actual download logic
        if (!targetFile.exists()) {
            targetFile.createNewFile()
            // Write some dummy data to simulate a model file
            targetFile.writeBytes("DUMMY_MODEL_DATA_${modelInfo.id}".toByteArray())
        }

        // Emit progress events
        for (progress in 1..10) {
            EventBus.shared.publish(SDKModelEvent.DownloadProgress(modelInfo.id, progress / 10f))
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
