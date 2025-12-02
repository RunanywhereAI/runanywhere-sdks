package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.services.download.DownloadService
import com.runanywhere.sdk.storage.FileSystem
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Model downloader for handling model downloads
 * Uses centralized ModelPathUtils for path consistency
 */
class ModelDownloader(
    private val fileSystem: FileSystem,
    private val downloadService: DownloadService,
    private val modelsDirectory: String = ModelPathUtils.getModelsDirectory()
) {
    private val logger = SDKLogger("ModelDownloader")

    suspend fun downloadModel(
        model: ModelInfo,
        progressCallback: (Float) -> Unit = {}
    ): String {
        // Ensure models directory exists
        if (!fileSystem.exists(modelsDirectory)) {
            fileSystem.createDirectory(modelsDirectory)
            logger.info("Created models directory: $modelsDirectory")
        }

        // Generate destination path
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val destinationPath = "$modelsDirectory/$fileName"

        logger.info("Downloading model ${model.id} to $destinationPath")

        // Convert Float progress to DownloadProgress and call downloadService
        return downloadService.downloadModel(model) { downloadProgress ->
            // Convert DownloadProgress percentage back to Float for callback
            progressCallback(downloadProgress.percentage.toFloat())
        }
    }

    /**
     * Check if model is already downloaded
     */
    suspend fun isModelDownloaded(model: ModelInfo): Boolean {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val filePath = "$modelsDirectory/$fileName"

        return fileSystem.exists(filePath) &&
                fileSystem.fileSize(filePath) == (model.downloadSize ?: 0L)
    }

    /**
     * Get local path for a model
     */
    fun getModelPath(model: ModelInfo): String {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        return "$modelsDirectory/$fileName"
    }

    /**
     * Download model with progress tracking as Flow
     */
    suspend fun downloadModelWithProgress(model: ModelInfo): Flow<Float> = flow {
        // Check if already downloaded
        if (isModelDownloaded(model)) {
            emit(1.0f)
            return@flow
        }

        // Ensure models directory exists
        if (!fileSystem.exists(modelsDirectory)) {
            fileSystem.createDirectory(modelsDirectory)
            logger.info("Created models directory: $modelsDirectory")
        }

        val destinationPath = getModelPath(model)

        // Download with progress
        emit(0.0f)

        var lastProgress = 0.0f
        downloadService.downloadModel(model) { downloadProgress ->
            lastProgress = downloadProgress.percentage.toFloat()
        }

        emit(lastProgress)
        emit(1.0f)
    }

    /**
     * Delete downloaded model
     */
    suspend fun deleteModel(model: ModelInfo): Boolean {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val filePath = "$modelsDirectory/$fileName"

        return if (fileSystem.exists(filePath)) {
            val deleted = fileSystem.delete(filePath)
            if (deleted) {
                logger.info("Deleted model: ${model.id}")
            }
            deleted
        } else {
            false
        }
    }
}
