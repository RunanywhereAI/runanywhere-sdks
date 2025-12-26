package com.runanywhere.sdk.infrastructure.modelmanagement.services

import com.runanywhere.sdk.data.models.ModelSearchCriteria
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.data.sync.SyncCoordinator
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.utils.SimpleInstant
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Model Info Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles model information management, caching, and synchronization
 */
class ModelInfoService(
    private val modelInfoRepository: ModelInfoRepository,
    private val syncCoordinator: SyncCoordinator?,
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
    suspend fun saveModel(model: ModelInfo) =
        mutex.withLock {
            logger.debug("Saving model: ${model.id}")

            try {
                // Validate model info
                validateModelInfo(model)

                // Save to repository
                modelInfoRepository.save(model)

                // Update cache
                cachedModels[model.id] = model

                logger.info("Model saved successfully: ${model.id}")
            } catch (e: Exception) {
                logger.error("Failed to save model: ${model.id} - ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Get model by ID
     * Equivalent to iOS: func getModel(by modelId: String) async throws -> ModelInfo?
     */
    suspend fun getModel(modelId: String): ModelInfo? =
        mutex.withLock {
            getModelInternal(modelId)
        }

    /**
     * Internal non-locking version for use within locked sections
     * Prevents deadlock when called from other methods that already hold the mutex
     */
    private suspend fun getModelInternal(modelId: String): ModelInfo? {
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
            val model = modelInfoRepository.fetch(modelId)

            if (model != null) {
                // Update cache
                cachedModels[modelId] = model
                logger.debug("Model loaded from repository: $modelId")
            } else {
                logger.debug("Model not found: $modelId")
            }

            return model
        } catch (e: Exception) {
            logger.error("Failed to get model: $modelId - ${e.message}")
            throw SDKError.RuntimeError("Database operation failed: ${e.message}")
        }
    }

    /**
     * Load models for specific frameworks
     * Equivalent to iOS: func loadModels(for frameworks: [InferenceFramework]) async throws -> [ModelInfo]
     */
    suspend fun loadModels(frameworks: List<InferenceFramework>): List<ModelInfo> =
        mutex.withLock {
            logger.debug("Loading models for frameworks: $frameworks")

            try {
                val models =
                    frameworks
                        .flatMap { framework ->
                            modelInfoRepository.fetchByFramework(framework)
                        }.distinct()

                // Update cache
                models.forEach { model ->
                    cachedModels[model.id] = model
                }

                logger.info("Loaded ${models.size} models for frameworks: $frameworks")
                return models
            } catch (e: Exception) {
                logger.error("Failed to load models for frameworks: $frameworks - ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Update model download status with local path
     * Enhanced version that accepts local path
     */
    suspend fun updateDownloadStatus(
        modelId: String,
        isDownloaded: Boolean,
        localPath: String? = null,
    ) = mutex.withLock {
        logger.debug("Updating download status for model: $modelId, isDownloaded: $isDownloaded, localPath: $localPath")

        try {
            // Get current model (use internal non-locking version to avoid deadlock)
            val currentModel =
                getModelInternal(modelId)
                    ?: throw SDKError.ModelNotFound(modelId)

            // Update download status with provided local path
            val updatedModel =
                currentModel.copy(
                    localPath = if (isDownloaded) localPath else null,
                    updatedAt = SimpleInstant.now(),
                )

            // Save updated model
            modelInfoRepository.save(updatedModel)

            // Update cache
            cachedModels[modelId] = updatedModel

            logger.info("Download status updated for model: $modelId with localPath: $localPath")
        } catch (e: Exception) {
            logger.error("Failed to update download status for model: $modelId - ${e.message}")
            throw SDKError.RuntimeError("Database operation failed: ${e.message}")
        }
    }

    /**
     * Load all stored models from repository
     * Equivalent to iOS: func loadStoredModels() async throws -> [ModelInfo]
     */
    suspend fun loadStoredModels(): List<ModelInfo> =
        mutex.withLock {
            logger.debug("Loading all stored models")

            try {
                val models = modelInfoRepository.fetchAll()

                // Update cache with all models
                models.forEach { model ->
                    cachedModels[model.id] = model
                }

                lastCacheUpdate = getCurrentTimeMillis()

                logger.info("Loaded ${models.size} stored models")
                return models
            } catch (e: Exception) {
                logger.error("Failed to load stored models - ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Update model download progress
     * Additional method not in iOS (Android-specific enhancement)
     */
    suspend fun updateDownloadProgress(
        modelId: String,
        progress: Float,
    ) = mutex.withLock {
        logger.debug("Updating download progress for model: $modelId, progress: $progress")

        try {
            val currentModel =
                getModel(modelId)
                    ?: throw SDKError.ModelNotFound(modelId)

            val updatedModel =
                currentModel.copy(
                    updatedAt = SimpleInstant.now(),
                )

            modelInfoRepository.save(updatedModel)
            cachedModels[modelId] = updatedModel
        } catch (e: Exception) {
            logger.error("Failed to update download progress for model: $modelId - ${e.message}")
            throw SDKError.RuntimeError("Database operation failed: ${e.message}")
        }
    }

    /**
     * Sync model info with remote
     * Equivalent to iOS: func syncModelInfo() async throws
     */

    /**
     * Initialize the service
     */
    suspend fun initialize() {
        logger.info("ModelInfoService initialized")
        // Load initial models if needed
        clearCache()
    }

    suspend fun syncModelInfo() =
        mutex.withLock {
            logger.debug("Syncing model info")

            try {
                // Use sync coordinator if available
                syncCoordinator?.let { coordinator ->
                    coordinator.syncModelInfo()
                } ?: run {
                    // Direct sync without coordinator
                    val remoteModels = modelInfoRepository.fetchAll()

                    remoteModels.forEach { model ->
                        modelInfoRepository.save(model)
                        cachedModels[model.id] = model
                    }
                }

                lastCacheUpdate = getCurrentTimeMillis()
                logger.info("Model info synced successfully")
            } catch (e: Exception) {
                logger.error("Failed to sync model info: ${e.message}")
                throw SDKError.NetworkError("Failed to sync model info: ${e.message}")
            }
        }

    /**
     * Get all models
     * Additional method for comprehensive model listing
     */
    suspend fun getAllModels(): List<ModelInfo> =
        mutex.withLock {
            logger.debug("Getting all models")

            try {
                val models = modelInfoRepository.fetchAll()

                // Update cache
                models.forEach { model ->
                    cachedModels[model.id] = model
                }

                return models
            } catch (e: Exception) {
                logger.error("Failed to get all models: ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Search models with criteria
     * Additional method for advanced model discovery
     */
    suspend fun searchModels(criteria: ModelSearchCriteria): List<ModelInfo> =
        mutex.withLock {
            logger.debug("Searching models with criteria: $criteria")

            try {
                // TODO: Implement searchModels in repository
                // val models = modelInfoRepository.searchModels(criteria)
                // For now, use getAllModels and filter
                val allModels = getAllModels()
                val models =
                    allModels.filter { model ->
                        (criteria.category == null || model.category == criteria.category) &&
                            (criteria.framework == null || model.preferredFramework == criteria.framework) &&
                            (criteria.format == null || model.format == criteria.format)
                    }
                logger.info("Found ${models.size} models matching criteria")
                return models
            } catch (e: Exception) {
                logger.error("Failed to search models: ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Delete model information
     * Additional method for model cleanup
     */
    suspend fun deleteModel(modelId: String) =
        mutex.withLock {
            logger.debug("Deleting model: $modelId")

            try {
                modelInfoRepository.delete(modelId)
                cachedModels.remove(modelId)

                logger.info("Model deleted: $modelId")
            } catch (e: Exception) {
                logger.error("Failed to delete model: $modelId - ${e.message}")
                throw SDKError.RuntimeError("Database operation failed: ${e.message}")
            }
        }

    /**
     * Update model last used timestamp
     * Track model usage for analytics
     */
    suspend fun updateModelLastUsed(modelId: String) =
        mutex.withLock {
            logger.debug("Updating last used timestamp for model: $modelId")

            try {
                val currentModel =
                    getModel(modelId)
                        ?: throw SDKError.ModelNotFound(modelId)

                val updatedModel =
                    currentModel.copy(
                        lastUsed = SimpleInstant.now(),
                        updatedAt = SimpleInstant.now(),
                    )

                modelInfoRepository.save(updatedModel)
                cachedModels[modelId] = updatedModel
            } catch (e: Exception) {
                logger.error("Failed to update last used for model: $modelId - ${e.message}")
                // Don't throw - this is not critical
            }
        }

    /**
     * Get cached models
     * Useful for offline access
     */
    suspend fun getCachedModels(): List<ModelInfo> =
        mutex.withLock {
            return cachedModels.values.toList()
        }

    /**
     * Clear model cache
     * Force refresh on next access
     */
    suspend fun clearCache() =
        mutex.withLock {
            logger.debug("Clearing model cache")
            cachedModels.clear()
            lastCacheUpdate = 0
            logger.info("Model cache cleared")
        }

    // Private helper methods

    private fun isCacheValid(): Boolean = (getCurrentTimeMillis() - lastCacheUpdate) < cacheValidityMs

    private fun validateModelInfo(model: ModelInfo) {
        if (model.id.isBlank()) {
            throw SDKError.ConfigurationError("Model ID cannot be blank")
        }

        if (model.name.isBlank()) {
            throw SDKError.ConfigurationError("Model name cannot be blank")
        }

        // Note: downloadURL, downloadSize, and memoryRequired are OPTIONAL during registration
        // They can be populated later during model discovery or download
        // iOS doesn't enforce these validations during registration

        logger.debug("Model validation passed for: ${model.id}")
    }
}
