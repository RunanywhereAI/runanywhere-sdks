package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.DownloadService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.io.File

/**
 * Model downloader for handling model downloads
 * Mirrors iOS ModelDownloader functionality
 */
class ModelDownloader(
    private val modelsDirectory: String = System.getProperty("user.home") + "/.runanywhere/models"
) {
    private val logger = SDKLogger("ModelDownloader")
    private val downloadService = DownloadService()

    suspend fun downloadModel(
        model: ModelInfo,
        progressCallback: (Float) -> Unit = {}
    ): String {
        // Ensure models directory exists
        val modelsDir = File(modelsDirectory)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
            logger.info("Created models directory: $modelsDirectory")
        }

        // Generate destination path
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val destinationPath = "$modelsDirectory/$fileName"

        logger.info("Downloading model ${model.id} to $destinationPath")

        return downloadService.downloadModel(model, destinationPath, progressCallback)
    }

    /**
     * Check if model is already downloaded
     */
    fun isModelDownloaded(model: ModelInfo): Boolean {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val file = File("$modelsDirectory/$fileName")

        return file.exists() && file.length() == model.downloadSize?.toLong() ?: 0L
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
        val modelsDir = File(modelsDirectory)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
            logger.info("Created models directory: $modelsDirectory")
        }

        val destinationPath = getModelPath(model)

        // Download with progress
        emit(0.0f)

        // For now, simulate progress (real implementation would track actual download)
        downloadService.downloadModel(model, destinationPath) { progress ->
            // Progress callback from download service
            kotlinx.coroutines.runBlocking {
                // This is not ideal but works for now
                // Real implementation would use channels or shared flow
            }
        }

        emit(1.0f)
    }

    /**
     * Delete downloaded model
     */
    fun deleteModel(model: ModelInfo): Boolean {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val file = File("$modelsDirectory/$fileName")

        return if (file.exists()) {
            val deleted = file.delete()
            if (deleted) {
                logger.info("Deleted model: ${model.id}")
            }
            deleted
        } else {
            false
        }
    }
}
