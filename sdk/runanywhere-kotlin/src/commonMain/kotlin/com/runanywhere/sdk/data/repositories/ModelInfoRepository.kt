package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory

/**
 * Repository protocol for model information persistence - exact match with iOS
 */
interface ModelInfoRepository {
    /**
     * Save a model info entity
     */
    suspend fun save(entity: ModelInfo)

    /**
     * Fetch a model by ID
     */
    suspend fun fetch(id: String): ModelInfo?

    /**
     * Fetch all models
     */
    suspend fun fetchAll(): List<ModelInfo>

    /**
     * Delete a model by ID
     */
    suspend fun delete(id: String)

    /**
     * Model-specific queries
     */
    suspend fun fetchByFramework(framework: InferenceFramework): List<ModelInfo>

    suspend fun fetchByCategory(category: ModelCategory): List<ModelInfo>

    suspend fun fetchDownloaded(): List<ModelInfo>

    /**
     * Update operations
     */
    suspend fun updateDownloadStatus(
        modelId: String,
        localPath: String?,
    )

    suspend fun updateLastUsed(modelId: String)

    /**
     * Sync support
     */
    suspend fun fetchPendingSync(): List<ModelInfo>

    suspend fun markSynced(ids: List<String>)
}
