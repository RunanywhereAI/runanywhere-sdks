package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.DownloadService
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
    fun getModelPath(model: ModelInfo): String? {
        val fileName = model.downloadURL?.substringAfterLast("/")
            ?: "${model.id}.gguf"
        val file = File("$modelsDirectory/$fileName")

        return if (file.exists()) file.absolutePath else null
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
