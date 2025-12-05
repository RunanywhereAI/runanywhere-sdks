package com.runanywhere.sdk.models

import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.storage.FileSystem
import com.runanywhere.sdk.services.download.DownloadService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Model handle for loaded models
 */
data class ModelHandle(
    val modelId: String,
    val modelPath: String
)

/**
 * Model Manager for handling model downloads and storage - Enhanced with real functionality
 * Integrates with KtorDownloadService and ModelLoadingService
 */
class ModelManager(
    private val fileSystem: FileSystem,
    private val downloadService: DownloadService
) {
    private val logger = SDKLogger("ModelManager")
    private val downloader = ModelDownloader(fileSystem, downloadService)
    private val integrityVerifier = ModelIntegrityVerifier(fileSystem)

    /**
     * Ensure model is available locally, download if needed
     * Returns the actual path where the model was downloaded
     */
    suspend fun ensureModel(modelInfo: ModelInfo): String = withContext(Dispatchers.IO) {
        logger.info("🔍 Ensuring model is available: ${modelInfo.id}")

        // First check if model already has a local path and file exists
        if (modelInfo.localPath != null && fileSystem.exists(modelInfo.localPath!!)) {
            logger.info("✅ Model already exists at: ${modelInfo.localPath}")
            return@withContext modelInfo.localPath!!
        }

        // Check if model file exists at expected path
        val expectedPath = getModelPath(modelInfo)
        if (fileSystem.exists(expectedPath)) {
            logger.info("✅ Model already exists at: $expectedPath")
            return@withContext expectedPath
        }

        logger.info("⬇️ Model not found locally, downloading: ${modelInfo.id}")

        // Emit download started event
        EventBus.publish(SDKModelEvent.DownloadStarted(modelInfo.id))

        try {
            // Use the real download service to download the model
            val downloadedPath = downloadService.downloadModel(modelInfo) { progress ->
                // Emit progress events
                EventBus.publish(SDKModelEvent.DownloadProgress(
                    modelInfo.id,
                    progress.percentage
                ))
            }

            logger.info("✅ Model downloaded successfully: ${modelInfo.id} -> $downloadedPath")

            // Verify model integrity if checksums are available
            logger.info("🔍 Verifying model integrity: ${modelInfo.id}")
            when (val verificationResult = integrityVerifier.verifyModel(modelInfo, downloadedPath)) {
                is VerificationResult.Success -> {
                    logger.info("✅ Model integrity verification passed: ${modelInfo.id}")
                }
                is VerificationResult.Failed -> {
                    logger.error("❌ Model integrity verification failed: ${verificationResult.reason}")
                    // Delete the corrupt file
                    fileSystem.delete(downloadedPath)
                    throw Exception("Model integrity verification failed: ${verificationResult.reason}")
                }
                is VerificationResult.Unsupported -> {
                    logger.warn("⚠️ Model integrity verification not possible: ${verificationResult.reason}")
                    // Continue anyway but log the warning
                }
            }

            // Emit download completed event
            EventBus.publish(SDKModelEvent.DownloadCompleted(modelInfo.id))

            return@withContext downloadedPath

        } catch (e: Exception) {
            logger.error("❌ Failed to download model: ${modelInfo.id}", e)
            EventBus.publish(SDKModelEvent.DownloadFailed(modelInfo.id, e))
            throw e
        }
    }

    /**
     * Load a model and return its handle
     */
    suspend fun loadModel(modelInfo: ModelInfo): ModelHandle {
        val path = ensureModel(modelInfo)
        return ModelHandle(modelInfo.id, path)
    }

    /**
     * Get the expected path for a model based on its info
     * Uses centralized ModelPathUtils for consistency
     */
    private fun getModelPath(modelInfo: ModelInfo): String {
        return ModelPathUtils.getModelPath(modelInfo)
    }

    /**
     * Check if a model is available locally
     * Uses centralized ModelPathUtils for path discovery
     */
    fun isModelAvailable(modelId: String): Boolean {
        // Use centralized path utility for model discovery
        val possiblePaths = ModelPathUtils.getPossibleModelPaths(modelId)
        return possiblePaths.any { fileSystem.existsSync(it) }
    }

    /**
     * Delete a model from local storage
     * Uses centralized ModelPathUtils for path discovery
     */
    suspend fun deleteModel(modelId: String) = withContext(Dispatchers.IO) {
        logger.info("🗑️ Deleting model: $modelId")

        try {
            // Use centralized path utility to find model locations
            val possibleDirs = ModelPathUtils.getPossibleModelPaths(modelId)

            var deletedAny = false
            for (dir in possibleDirs) {
                if (fileSystem.exists(dir)) {
                    fileSystem.deleteRecursively(dir)
                    deletedAny = true
                    logger.info("✅ Deleted model directory: $dir")
                }
            }

            if (deletedAny) {
                EventBus.publish(SDKModelEvent.DeleteCompleted(modelId))
            } else {
                logger.warn("⚠️ No model files found to delete for: $modelId")
            }

        } catch (e: Exception) {
            logger.error("❌ Failed to delete model: $modelId", e)
            EventBus.publish(SDKModelEvent.DeleteFailed(modelId, e))
            throw e
        }
    }

    /**
     * Get total storage used by all models
     * Uses centralized ModelPathUtils for path
     */
    suspend fun getTotalModelsSize(): Long = withContext(Dispatchers.IO) {
        val modelsDir = ModelPathUtils.getModelsDirectory()
        return@withContext if (fileSystem.exists(modelsDir)) {
            calculateDirectorySize(modelsDir)
        } else {
            0L
        }
    }

    /**
     * Clear all models from storage
     * Uses centralized ModelPathUtils for path
     */
    suspend fun clearAllModels() = withContext(Dispatchers.IO) {
        logger.info("🗑️ Clearing all models")

        try {
            val modelsDir = ModelPathUtils.getModelsDirectory()
            if (fileSystem.exists(modelsDir)) {
                fileSystem.deleteRecursively(modelsDir)
                logger.info("✅ All models cleared")
            }
        } catch (e: Exception) {
            logger.error("❌ Failed to clear all models", e)
            throw e
        }
    }

    /**
     * Helper to calculate directory size recursively
     */
    private suspend fun calculateDirectorySize(path: String): Long {
        return try {
            if (!fileSystem.exists(path)) {
                0L
            } else if (fileSystem.isDirectory(path)) {
                val files = fileSystem.listFiles(path)
                var totalSize = 0L
                for (file in files) {
                    val filePath = "$path/$file"
                    totalSize += if (fileSystem.isDirectory(filePath)) {
                        calculateDirectorySize(filePath)
                    } else {
                        fileSystem.fileSize(filePath)
                    }
                }
                totalSize
            } else {
                fileSystem.fileSize(path)
            }
        } catch (e: Exception) {
            logger.warn("Failed to calculate directory size for $path: ${e.message}")
            0L
        }
    }
}
