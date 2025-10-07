package com.runanywhere.whisperkit.storage

import com.runanywhere.sdk.storage.ModelStorageStrategy
import com.runanywhere.sdk.storage.ModelStorageDetails
import com.runanywhere.sdk.storage.ModelDetectionResult
import com.runanywhere.sdk.storage.DownloadProgress
import com.runanywhere.sdk.storage.DownloadError
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.whisperkit.models.WhisperModelInfo
import com.runanywhere.whisperkit.models.WhisperModelType
import com.runanywhere.whisperkit.models.WhisperError

/**
 * WhisperKit-specific storage strategy that extends the generic ModelStorageStrategy
 * Matches iOS WhisperKitStorageStrategy pattern with complete interface parity
 * Provides Whisper-specific model management, download, and validation capabilities
 */
abstract class WhisperStorageStrategy : ModelStorageStrategy {

    /**
     * Get path for a specific Whisper model type
     * @param type The Whisper model type
     * @return The file system path to the model
     */
    abstract suspend fun getModelPath(type: WhisperModelType): String

    /**
     * Download a Whisper model by type with enhanced progress tracking
     * @param type The Whisper model type to download
     * @param onProgress Progress callback with DownloadProgress updates
     */
    abstract suspend fun downloadModel(
        type: WhisperModelType,
        onProgress: (DownloadProgress) -> Unit = {}
    )

    /**
     * Check if a specific Whisper model is downloaded
     * @param type The Whisper model type
     * @return true if the model is available locally
     */
    abstract suspend fun isModelDownloaded(type: WhisperModelType): Boolean

    /**
     * Get model information for a specific type
     * @param type The Whisper model type
     * @return WhisperModelInfo with current status
     */
    abstract suspend fun getModelInfo(type: WhisperModelType): WhisperModelInfo

    /**
     * Get all available Whisper models with their current status
     * @return List of all WhisperModelInfo objects
     */
    abstract suspend fun getAllModels(): List<WhisperModelInfo>

    /**
     * Delete a specific Whisper model from storage
     * @param type The Whisper model type to delete
     * @return true if deletion was successful
     */
    abstract suspend fun deleteModel(type: WhisperModelType): Boolean

    /**
     * Get total storage used by all Whisper models
     * @return Total bytes used by Whisper models
     */
    abstract suspend fun getTotalStorageUsed(): Long

    /**
     * Clean up old models, keeping only specified types
     * @param keepTypes List of model types to preserve
     */
    abstract suspend fun cleanupOldModels(keepTypes: List<WhisperModelType> = emptyList())

    /**
     * Update last used timestamp for a model
     * @param type The model type that was used
     */
    abstract suspend fun updateLastUsed(type: WhisperModelType)

    // ModelStorageStrategy implementation with iOS-aligned behavior
    override suspend fun findModelPath(modelId: String, modelFolder: String): String? {
        // Map generic model ID to WhisperModelType
        val whisperType = WhisperModelType.fromModelName(modelId) ?: return null
        return if (isModelDownloaded(whisperType)) {
            getModelPath(whisperType)
        } else {
            null
        }
    }

    override suspend fun detectModel(modelFolder: String): ModelDetectionResult? {
        return try {
            // For Whisper models, we look for .bin files
            val storageInfo = getModelStorageInfo(modelFolder)
            if (storageInfo != null) {
                ModelDetectionResult(
                    format = storageInfo.format,
                    sizeBytes = storageInfo.totalSize
                )
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    override suspend fun isValidModelStorage(modelFolder: String): Boolean {
        return try {
            // Check if any Whisper model exists in the folder
            WhisperModelType.values().any { type ->
                try {
                    isModelDownloaded(type)
                } catch (e: Exception) {
                    false
                }
            }
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun getModelStorageInfo(modelFolder: String): ModelStorageDetails? {
        return try {
            // Find the first available model and return its info
            for (type in WhisperModelType.values()) {
                if (isModelDownloaded(type)) {
                    val modelInfo = getModelInfo(type)
                    return ModelStorageDetails(
                        format = ModelFormat.BIN,
                        totalSize = type.approximateSizeMB * 1024 * 1024L, // Convert to bytes
                        fileCount = 1,
                        primaryFile = type.fileName,
                        isDirectoryBased = false,
                        lastModified = modelInfo.lastUsed,
                        checksum = null,
                        files = listOf(type.fileName)
                    )
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    override fun canHandle(model: ModelInfo): Boolean {
        // Handle speech recognition models compatible with WhisperKit
        return model.category == ModelCategory.SPEECH_RECOGNITION &&
               (model.preferredFramework?.name?.contains("whisper", ignoreCase = true) == true ||
                model.compatibleFrameworks.any { it.name.contains("whisper", ignoreCase = true) } ||
                WhisperModelType.fromModelName(model.id) != null)
    }

    override suspend fun getEstimatedSize(model: ModelInfo): Long? {
        val whisperType = WhisperModelType.fromModelName(model.id) ?: return null
        return whisperType.approximateSizeMB * 1024 * 1024L // Convert to bytes
    }

    override suspend fun cancelDownload(model: ModelInfo): Boolean {
        // WhisperKit models don't support download cancellation in the current implementation
        // This could be enhanced to support cancellation in the future
        return false
    }

    override suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((DownloadProgress) -> Unit)?
    ): String {
        // Map to WhisperModelType and download
        val whisperType = WhisperModelType.fromModelName(model.id)
            ?: throw DownloadError.ModelNotFound(model.id)

        try {
            if (progressHandler != null) {
                downloadModel(whisperType, progressHandler)
            } else {
                downloadModel(whisperType)
            }

            return getModelPath(whisperType)
        } catch (e: WhisperError.ModelDownloadFailed) {
            throw DownloadError.NetworkError(e)
        } catch (e: WhisperError.NetworkError) {
            throw DownloadError.NetworkError(e)
        } catch (e: Exception) {
            throw DownloadError.UnknownError("Failed to download Whisper model: ${e.message}", e)
        }
    }

    // Legacy method for backward compatibility
    suspend fun downloadModelWithSimpleProgress(
        type: WhisperModelType,
        onProgress: (Float) -> Unit = {}
    ) {
        downloadModel(type) { progress ->
            onProgress(progress.percentage.toFloat())
        }
    }
}

/**
 * Default implementation of WhisperStorageStrategy
 */
expect class DefaultWhisperStorage() : WhisperStorageStrategy
