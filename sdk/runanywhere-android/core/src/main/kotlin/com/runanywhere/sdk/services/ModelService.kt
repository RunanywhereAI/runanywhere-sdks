package com.runanywhere.sdk.services

import android.content.Context
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.data.repositories.ModelInfoRepositoryImpl
import com.runanywhere.sdk.download.DownloadTask
import com.runanywhere.sdk.download.ModelDownloadManager
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.network.MockNetworkService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * Model Service - coordinates model operations across repository, network, and downloads
 * Exact match with iOS ModelInfoService pattern
 */
class ModelService(
    private val context: Context,
    private val repository: ModelInfoRepository = ModelInfoRepositoryImpl(),
    private val networkService: MockNetworkService = MockNetworkService(),
    private val downloadManager: ModelDownloadManager = ModelDownloadManager(context, repository)
) {

    /**
     * Initialize the service and load models
     */
    suspend fun initialize() {
        withContext(Dispatchers.IO) {
            // Load models from network (or mock in development)
            val models = networkService.fetchModels()

            // Save to repository
            models.forEach { model ->
                repository.save(model)
            }
        }
    }

    /**
     * Get all available models
     */
    suspend fun getAllModels(): List<ModelInfo> {
        return repository.fetchAll()
    }

    /**
     * Get models by category
     */
    suspend fun getModelsByCategory(category: ModelCategory): List<ModelInfo> {
        return repository.fetchByCategory(category)
    }

    /**
     * Get models by framework
     */
    suspend fun getModelsByFramework(framework: LLMFramework): List<ModelInfo> {
        return repository.fetchByFramework(framework)
    }

    /**
     * Get downloaded models
     */
    suspend fun getDownloadedModels(): List<ModelInfo> {
        return repository.fetchDownloaded()
    }

    /**
     * Get a specific model
     */
    suspend fun getModel(modelId: String): ModelInfo? {
        return repository.fetch(modelId)
    }

    /**
     * Download a model
     */
    suspend fun downloadModel(modelId: String): DownloadTask {
        val model = repository.fetch(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        return downloadManager.downloadModel(model)
    }

    /**
     * Download a model with simplified progress
     */
    suspend fun downloadModelWithProgress(
        modelId: String,
        onProgress: (Float) -> Unit
    ): Flow<DownloadStatus> = flow {
        val model = repository.fetch(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        val task = downloadManager.downloadModel(model)

        task.progress.collect { progress ->
            onProgress(progress.progressPercent / 100f)

            emit(
                DownloadStatus(
                    modelId = modelId,
                    progress = progress.progressPercent / 100f,
                    bytesDownloaded = progress.bytesDownloaded,
                    totalBytes = progress.totalBytes,
                    speed = progress.formattedSpeed,
                    isCompleted = progress.state is com.runanywhere.sdk.download.DownloadState.COMPLETED,
                    isFailed = progress.state is com.runanywhere.sdk.download.DownloadState.FAILED,
                    error = (progress.state as? com.runanywhere.sdk.download.DownloadState.FAILED)?.error?.message
                )
            )
        }
    }

    /**
     * Cancel a download
     */
    fun cancelDownload(taskId: String) {
        downloadManager.cancelDownload(taskId)
    }

    /**
     * Pause a download
     */
    fun pauseDownload(taskId: String) {
        downloadManager.pauseDownload(taskId)
    }

    /**
     * Resume a download
     */
    fun resumeDownload(taskId: String) {
        downloadManager.resumeDownload(taskId)
    }

    /**
     * Delete a model
     */
    suspend fun deleteModel(modelId: String): Boolean {
        val model = repository.fetch(modelId) ?: return false

        // Delete files
        val deleted = downloadManager.deleteModel(model)

        if (deleted) {
            // Update repository
            repository.updateDownloadStatus(modelId, null)
        }

        return deleted
    }

    /**
     * Get storage info
     */
    fun getStorageInfo(): StorageInfo {
        val totalUsed = downloadManager.getTotalStorageUsed()
        val totalAvailable = context.getExternalFilesDir(null)?.freeSpace ?: 0L

        return StorageInfo(
            totalUsed = totalUsed,
            totalAvailable = totalAvailable,
            formattedUsed = formatBytes(totalUsed),
            formattedAvailable = formatBytes(totalAvailable)
        )
    }

    /**
     * Clean up partial downloads
     */
    suspend fun cleanupPartialDownloads() {
        downloadManager.cleanupPartialDownloads()
    }

    /**
     * Check if model is downloaded
     */
    suspend fun isModelDownloaded(modelId: String): Boolean {
        val model = repository.fetch(modelId) ?: return false
        return model.isDownloaded
    }

    /**
     * Update model usage stats
     */
    suspend fun recordModelUsage(modelId: String) {
        repository.updateLastUsed(modelId)
    }

    /**
     * Get recommended models based on device capabilities
     */
    suspend fun getRecommendedModels(): List<ModelInfo> {
        val allModels = repository.fetchAll()
        val availableMemory = Runtime.getRuntime().maxMemory()

        // Filter models that fit in available memory
        return allModels.filter { model ->
            val requiredMemory = model.memoryRequired ?: 0L
            requiredMemory <= availableMemory * 0.7 // Use 70% as safe threshold
        }.sortedBy { it.memoryRequired }
    }

    /**
     * Search models by name or tags
     */
    suspend fun searchModels(query: String): List<ModelInfo> {
        val allModels = repository.fetchAll()
        val lowerQuery = query.lowercase()

        return allModels.filter { model ->
            model.name.lowercase().contains(lowerQuery) ||
                    model.id.lowercase().contains(lowerQuery) ||
                    model.metadata?.tags?.any { it.lowercase().contains(lowerQuery) } == true
        }
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            else -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
        }
    }
}

/**
 * Download status information
 */
data class DownloadStatus(
    val modelId: String,
    val progress: Float,
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val speed: String,
    val isCompleted: Boolean,
    val isFailed: Boolean,
    val error: String? = null
)

/**
 * Storage information
 */
data class StorageInfo(
    val totalUsed: Long,
    val totalAvailable: Long,
    val formattedUsed: String,
    val formattedAvailable: String
)
