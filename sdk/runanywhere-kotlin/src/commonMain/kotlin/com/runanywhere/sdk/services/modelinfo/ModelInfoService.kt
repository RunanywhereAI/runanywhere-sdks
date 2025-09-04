package com.runanywhere.sdk.services.modelinfo

import com.runanywhere.sdk.data.models.LLMFramework
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.ModelRegistryEntry
import com.runanywhere.sdk.data.models.ModelSearchCriteria
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.repository.ModelInfoRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Model Info Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles model information management, caching, and synchronization
 */
class ModelInfoService(
    private val modelInfoRepository: ModelInfoRepository,
    private val syncCoordinator: SyncCoordinator?
) {

    private val logger = SDKLogger("ModelInfoService")
    private val mutex = Mutex()

    private val cachedModels = mutableMapOf<String, ModelInfo>()
    private var lastCacheUpdate: Long = 0
    private val cacheValidityMs = 5 * 60 * 1000L // 5 minutes

    /**
     * Save model information
     * Equivalent to iOS: func saveModel(_ model: ModelInfo) async throws
     */
    suspend fun saveModel(model: ModelInfo) = mutex.withLock {
        logger.debug("Saving model: ${model.id}")

        try {
            // Validate model info
            validateModelInfo(model)

            // Save to repository
            modelInfoRepository.saveModel(model)

            // Update cache
            cachedModels[model.id] = model

            logger.info("Model saved successfully: ${model.id}")

        } catch (e: Exception) {
            logger.error("Failed to save model: ${model.id}", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Get model by ID
     * Equivalent to iOS: func getModel(by modelId: String) async throws -> ModelInfo?
     */
    suspend fun getModel(modelId: String): ModelInfo? = mutex.withLock {
        logger.debug("Getting model: $modelId")

        try {
            // Check cache first
            cachedModels[modelId]?.let { cachedModel ->
                if (isCacheValid()) {
                    logger.debug("Returning cached model: $modelId")
                    return cachedModel
                }
            }

            // Load from repository
            val model = modelInfoRepository.getModel(modelId)

            if (model != null) {
                // Update cache
                cachedModels[modelId] = model
                logger.debug("Model loaded from repository: $modelId")
            } else {
                logger.debug("Model not found: $modelId")
            }

            return model

        } catch (e: Exception) {
            logger.error("Failed to get model: $modelId", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Load models for specific frameworks
     * Equivalent to iOS: func loadModels(for frameworks: [LLMFramework]) async throws -> [ModelInfo]
     */
    suspend fun loadModels(frameworks: List<LLMFramework>): List<ModelInfo> = mutex.withLock {
        logger.debug("Loading models for frameworks: $frameworks")

        try {
            val models = modelInfoRepository.getModelsForFrameworks(frameworks)

            // Update cache
            models.forEach { model ->
                cachedModels[model.id] = model
            }

            logger.info("Loaded ${models.size} models for frameworks: $frameworks")
            return models

        } catch (e: Exception) {
            logger.error("Failed to load models for frameworks: $frameworks", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Update model download status
     * Equivalent to iOS: func updateDownloadStatus(_ modelId: String, isDownloaded: Bool) async throws
     */
    suspend fun updateDownloadStatus(modelId: String, isDownloaded: Boolean) = mutex.withLock {
        logger.debug("Updating download status for model: $modelId, isDownloaded: $isDownloaded")

        try {
            // Get current model
            val currentModel = getModel(modelId)
                ?: throw SDKError.ModelNotFound(modelId)

            // Update download status
            val updatedModel = currentModel.copy(
                isDownloaded = isDownloaded,
                updatedAt = Clock.System.now().toEpochMilliseconds()
            )

            // Save updated model
            modelInfoRepository.saveModel(updatedModel)

            // Update cache
            cachedModels[modelId] = updatedModel

            logger.info("Download status updated for model: $modelId")

        } catch (e: Exception) {
            logger.error("Failed to update download status for model: $modelId", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Update model download progress
     * Additional method not in iOS (Android-specific enhancement)
     */
    suspend fun updateDownloadProgress(modelId: String, progress: Float) = mutex.withLock {
        logger.debug("Updating download progress for model: $modelId, progress: $progress")

        try {
            val currentModel = getModel(modelId)
                ?: throw SDKError.ModelNotFound(modelId)

            val updatedModel = currentModel.copy(
                downloadProgress = progress,
                updatedAt = Clock.System.now().toEpochMilliseconds()
            )

            modelInfoRepository.saveModel(updatedModel)
            cachedModels[modelId] = updatedModel

        } catch (e: Exception) {
            logger.error("Failed to update download progress for model: $modelId", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Sync model info with remote
     * Equivalent to iOS: func syncModelInfo() async throws
     */
    suspend fun syncModelInfo() = mutex.withLock {
        logger.debug("Syncing model info")

        try {
            // Use sync coordinator if available
            syncCoordinator?.let { coordinator ->
                coordinator.syncModelInfo()
            } ?: run {
                // Direct sync without coordinator
                val remoteModels = modelInfoRepository.fetchRemoteModels()

                remoteModels.forEach { model ->
                    modelInfoRepository.saveModel(model)
                    cachedModels[model.id] = model
                }
            }

            lastCacheUpdate = Clock.System.now().toEpochMilliseconds()
            logger.info("Model info synced successfully")

        } catch (e: Exception) {
            logger.error("Failed to sync model info", e)
            throw SDKError.NetworkError("Failed to sync model info: ${e.message}")
        }
    }

    /**
     * Get all models
     * Additional method for comprehensive model listing
     */
    suspend fun getAllModels(): List<ModelInfo> = mutex.withLock {
        logger.debug("Getting all models")

        try {
            val models = modelInfoRepository.getAllModels()

            // Update cache
            models.forEach { model ->
                cachedModels[model.id] = model
            }

            return models

        } catch (e: Exception) {
            logger.error("Failed to get all models", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Search models with criteria
     * Additional method for advanced model discovery
     */
    suspend fun searchModels(criteria: ModelSearchCriteria): List<ModelInfo> = mutex.withLock {
        logger.debug("Searching models with criteria: $criteria")

        try {
            val models = modelInfoRepository.searchModels(criteria)
            logger.info("Found ${models.size} models matching criteria")
            return models

        } catch (e: Exception) {
            logger.error("Failed to search models", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Delete model information
     * Additional method for model cleanup
     */
    suspend fun deleteModel(modelId: String) = mutex.withLock {
        logger.debug("Deleting model: $modelId")

        try {
            modelInfoRepository.deleteModel(modelId)
            cachedModels.remove(modelId)

            logger.info("Model deleted: $modelId")

        } catch (e: Exception) {
            logger.error("Failed to delete model: $modelId", e)
            throw SDKError.DatabaseInitializationFailed(e)
        }
    }

    /**
     * Update model last used timestamp
     * Track model usage for analytics
     */
    suspend fun updateModelLastUsed(modelId: String) = mutex.withLock {
        logger.debug("Updating last used timestamp for model: $modelId")

        try {
            val currentModel = getModel(modelId)
                ?: throw SDKError.ModelNotFound(modelId)

            val updatedModel = currentModel.copy(
                lastUsed = Clock.System.now().toEpochMilliseconds(),
                updatedAt = Clock.System.now().toEpochMilliseconds()
            )

            modelInfoRepository.saveModel(updatedModel)
            cachedModels[modelId] = updatedModel

        } catch (e: Exception) {
            logger.error("Failed to update last used for model: $modelId", e)
            // Don't throw - this is not critical
        }
    }

    /**
     * Get cached models
     * Useful for offline access
     */
    suspend fun getCachedModels(): List<ModelInfo> = mutex.withLock {
        return cachedModels.values.toList()
    }

    /**
     * Clear model cache
     * Force refresh on next access
     */
    suspend fun clearCache() = mutex.withLock {
        logger.debug("Clearing model cache")
        cachedModels.clear()
        lastCacheUpdate = 0
        logger.info("Model cache cleared")
    }

    // Private helper methods

    private fun isCacheValid(): Boolean {
        return (Clock.System.now().toEpochMilliseconds() - lastCacheUpdate) < cacheValidityMs
    }

    private fun validateModelInfo(model: ModelInfo) {
        if (model.id.isBlank()) {
            throw SDKError.ConfigurationError("Model ID cannot be blank")
        }

        if (model.name.isBlank()) {
            throw SDKError.ConfigurationError("Model name cannot be blank")
        }

        if (model.downloadURL.isBlank()) {
            throw SDKError.ConfigurationError("Model download URL cannot be blank")
        }

        if (model.downloadSize <= 0) {
            throw SDKError.ConfigurationError("Model download size must be positive")
        }

        if (model.memoryRequired <= 0) {
            throw SDKError.ConfigurationError("Model memory required must be positive")
        }

        logger.debug("Model validation passed for: ${model.id}")
    }
}
