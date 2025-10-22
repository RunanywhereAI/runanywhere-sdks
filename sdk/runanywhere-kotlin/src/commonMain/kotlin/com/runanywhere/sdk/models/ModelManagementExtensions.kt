package com.runanywhere.sdk.models

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.models.enums.LLMFramework
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Model Management Extensions for RunAnywhere SDK - EXACT copy of iOS RunAnywhere+ModelManagement.swift
 *
 * This object provides static methods for model management operations.
 * All methods are suspend functions following Kotlin coroutine patterns.
 */
object RunAnywhereModelManagement {

    private val logger = SDKLogger("ModelManagement")

    /**
     * Load a model by identifier and return model info - EXACT copy of iOS implementation
     * @param modelIdentifier The model to load
     * @return Information about the loaded model
     */
    suspend fun loadModelWithInfo(modelIdentifier: String): ModelInfo = withContext(Dispatchers.Default) {
        EventBus.publish(SDKModelEvent.LoadStarted(modelIdentifier))

        try {
            // Use existing service logic directly
            val loadedModel = ServiceContainer.shared.modelLoadingService.loadModel(modelIdentifier)

            // CRITICAL: Set the loaded model in the generation service so it can use it for inference
            ServiceContainer.shared.generationService.setCurrentModel(loadedModel)
            logger.info("✅ Model loaded and set in GenerationService: ${loadedModel.model.id}")

            EventBus.publish(SDKModelEvent.LoadCompleted(modelIdentifier))
            return@withContext loadedModel.model
        } catch (error: Exception) {
            EventBus.publish(SDKModelEvent.LoadFailed(modelIdentifier, error))
            throw error
        }
    }

    /**
     * Unload the currently loaded model - EXACT copy of iOS implementation
     */
    suspend fun unloadModel() = withContext(Dispatchers.Default) {
        EventBus.publish(SDKModelEvent.UnloadStarted)

        try {
            // Get the current model ID from generation service
            // TODO: Implement when generation service supports getCurrentModel()
            // val currentModel = ServiceContainer.shared.generationService.getCurrentModel()

            // For now, unload all models as a placeholder
            ServiceContainer.shared.modelLoadingService.clearAllModels()

            EventBus.publish(SDKModelEvent.UnloadCompleted)
        } catch (error: Exception) {
            EventBus.publish(SDKModelEvent.UnloadFailed(error))
            throw error
        }
    }

    /**
     * List all available models - EXACT copy of iOS implementation
     * @return Array of available models
     */
    suspend fun listAvailableModels(): List<ModelInfo> = withContext(Dispatchers.Default) {
        EventBus.publish(SDKModelEvent.ListRequested)

        // Use model registry to discover models
        val models = ServiceContainer.shared.modelRegistry.discoverModels()
        EventBus.publish(SDKModelEvent.ListCompleted(models))
        return@withContext models
    }

    /**
     * Download a model - EXACT copy of iOS implementation
     * @param modelIdentifier The model to download
     */
    suspend fun downloadModel(modelIdentifier: String) = withContext(Dispatchers.IO) {
        EventBus.publish(SDKModelEvent.DownloadStarted(modelIdentifier))

        try {
            // Get the model info first
            val modelInfoService = ServiceContainer.shared.modelInfoService

            // Log available models for debugging
            val allModels = modelInfoService.getAllModels()
            logger.debug("Available models in database: ${allModels.map { it.id }}")
            logger.debug("Looking for model: $modelIdentifier")

            var modelInfo = modelInfoService.getModel(modelIdentifier)

            if (modelInfo == null) {
                logger.error("Model not found in database: $modelIdentifier")

                // Try to find in registry as fallback
                val registryModel = ServiceContainer.shared.modelRegistry.getModel(modelIdentifier)
                if (registryModel != null) {
                    logger.debug("Found model in registry, saving to database")
                    modelInfoService.saveModel(registryModel)

                    // Now try again
                    modelInfo = modelInfoService.getModel(modelIdentifier)
                        ?: throw SDKError.ModelNotFound(modelIdentifier)
                } else {
                    throw SDKError.ModelNotFound(modelIdentifier)
                }
            }

            // Use the download service to download the model
            val downloadService = ServiceContainer.shared.downloadService
            val downloadedPath = downloadService.downloadModel(modelInfo) { progress ->
                // Progress is already handled by the download service
                // which publishes events through the ModelManager
            }

            // Update model info with local path after successful download
            val updatedModel = modelInfo.copy(localPath = downloadedPath)
            modelInfoService.saveModel(updatedModel)

            // Also update the model in the registry with the new local path
            ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

            EventBus.publish(SDKModelEvent.DownloadCompleted(modelIdentifier))

        } catch (error: Exception) {
            EventBus.publish(SDKModelEvent.DownloadFailed(modelIdentifier, error))
            throw error
        }
    }

    /**
     * Delete a model - EXACT copy of iOS implementation
     * @param modelIdentifier The model to delete
     */
    suspend fun deleteModel(modelIdentifier: String) = withContext(Dispatchers.IO) {
        EventBus.publish(SDKModelEvent.DeleteStarted(modelIdentifier))

        try {
            // Use model manager to delete model
            ServiceContainer.shared.modelManager.deleteModel(modelIdentifier)

            // Also remove from registry and database
            ServiceContainer.shared.modelRegistry.removeModel(modelIdentifier)
            // TODO: Add deletion from modelInfoService when it supports deletion

            EventBus.publish(SDKModelEvent.DeleteCompleted(modelIdentifier))
        } catch (error: Exception) {
            EventBus.publish(SDKModelEvent.DeleteFailed(modelIdentifier, error))
            throw error
        }
    }

    /**
     * Add a custom model from URL - EXACT copy of iOS implementation
     * @param url URL to the model
     * @param name Display name for the model
     * @param type Model type
     * @return Model information
     */
    @OptIn(ExperimentalUuidApi::class)
    suspend fun addModelFromURL(
        url: String,
        name: String,
        type: String
    ): ModelInfo = withContext(Dispatchers.Default) {
        EventBus.publish(SDKModelEvent.CustomModelAdded(name, url))

        // Create basic model info (this would need proper implementation)
        val modelInfo = ModelInfo(
            id = Uuid.random().toString(),
            name = name,
            category = ModelCategory.LANGUAGE, // Default to language model
            format = ModelFormat.GGUF, // Default
            downloadURL = url,
            localPath = null,
            downloadSize = null,
            memoryRequired = 1024L * 1024 * 1024, // Default 1GB
            compatibleFrameworks = listOf(LLMFramework.LLAMA_CPP),
            preferredFramework = LLMFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = null
        )

        // Register the model
        ServiceContainer.shared.modelRegistry.registerModel(modelInfo)

        return@withContext modelInfo
    }

    /**
     * Register a built-in model - EXACT copy of iOS implementation
     * @param model The model to register
     */
    suspend fun registerBuiltInModel(model: ModelInfo) = withContext(Dispatchers.Default) {
        // Register the model in the model registry
        ServiceContainer.shared.modelRegistry.registerModel(model)

        EventBus.publish(SDKModelEvent.BuiltInModelRegistered(model.id))
    }

    /**
     * Get download progress for a model
     * @param modelIdentifier The model identifier
     * @return Current download progress or null if not downloading
     */
    fun getDownloadProgress(modelIdentifier: String): Double? {
        val activeDownloads = ServiceContainer.shared.downloadService.getActiveDownloads()
        val modelDownload = activeDownloads.find { it.modelId == modelIdentifier }

        // TODO: Get actual progress from the download task
        // This would require enhancing the download task to provide current progress
        return null
    }

    /**
     * Cancel download for a model
     * @param modelIdentifier The model identifier
     */
    fun cancelDownload(modelIdentifier: String) {
        ServiceContainer.shared.downloadService.cancelDownload(modelIdentifier)
        EventBus.publish(SDKModelEvent.DownloadCancelled(modelIdentifier))
    }

    /**
     * Check if a model is currently being downloaded
     * @param modelIdentifier The model identifier
     * @return True if currently downloading
     */
    fun isDownloading(modelIdentifier: String): Boolean {
        return ServiceContainer.shared.downloadService.isDownloading(modelIdentifier)
    }

    /**
     * Get storage statistics for all models
     * @return Storage statistics
     */
    suspend fun getStorageStatistics(): ModelStorageStatistics = withContext(Dispatchers.IO) {
        val totalSize = ServiceContainer.shared.modelManager.getTotalModelsSize()
        val downloadedModels = ServiceContainer.shared.modelRegistry.getAllModels()
            .filter { it.localPath != null }

        return@withContext ModelStorageStatistics(
            totalStorageUsed = totalSize,
            modelCount = downloadedModels.size,
            downloadedModels = downloadedModels
        )
    }
}

/**
 * Storage statistics for models
 */
data class ModelStorageStatistics(
    val totalStorageUsed: Long,
    val modelCount: Int,
    val downloadedModels: List<ModelInfo>
)
