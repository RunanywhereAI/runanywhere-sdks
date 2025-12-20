package com.runanywhere.sdk.storage

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Model storage strategy interface matching iOS ModelStorageStrategy protocol
 * Extends DownloadStrategy to provide both download and storage capabilities
 * This matches the iOS hierarchy: DownloadStrategy -> ModelStorageStrategy
 */
interface ModelStorageStrategy : DownloadStrategy {
    /**
     * Find the model file/folder path in storage
     * @param modelId The model identifier
     * @param modelFolder The folder to search in
     * @return Path to the model if found, null otherwise
     */
    suspend fun findModelPath(
        modelId: String,
        modelFolder: String,
    ): String?

    /**
     * Detect if a model exists in the given folder and return its details
     * @param modelFolder The folder to examine
     * @return Model detection result if valid model found, null otherwise
     */
    suspend fun detectModel(modelFolder: String): ModelDetectionResult?

    /**
     * Check if the model storage is valid (all required files present)
     * @param modelFolder The folder to validate
     * @return true if storage is valid and complete
     */
    suspend fun isValidModelStorage(modelFolder: String): Boolean

    /**
     * Get comprehensive information about model storage
     * @param modelFolder The folder to examine
     * @return Detailed storage information if available
     */
    suspend fun getModelStorageInfo(modelFolder: String): ModelStorageDetails?

    // DownloadStrategy implementation with enhanced progress tracking
    override suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((DownloadProgress) -> Unit)?,
    ): String

    // Legacy method for backward compatibility
    suspend fun downloadWithSimpleProgress(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Float) -> Unit)?,
    ): String =
        download(model, destinationFolder) { progress ->
            progressHandler?.invoke(progress.percentage.toFloat())
        }
}

/**
 * Result of model detection
 */
data class ModelDetectionResult(
    val format: ModelFormat,
    val sizeBytes: Long,
)

/**
 * Information about model storage details
 * Matches iOS ModelStorageDetails struct with comprehensive metadata
 */
data class ModelStorageDetails(
    val format: ModelFormat,
    val totalSize: Long,
    val fileCount: Int,
    val primaryFile: String? = null,
    val isDirectoryBased: Boolean = false,
    val lastModified: Long? = null,
    val checksum: String? = null,
    val files: List<String> = emptyList(),
) {
    /**
     * Human-readable size string
     */
    val formattedSize: String
        get() = formatBytes(totalSize)

    /**
     * Whether this is a single-file model
     */
    val isSingleFile: Boolean
        get() = fileCount == 1 && !isDirectoryBased

    companion object {
        private fun formatBytes(bytes: Long): String {
            val units = arrayOf("B", "KB", "MB", "GB", "TB")
            var size = bytes.toDouble()
            var unitIndex = 0

            while (size >= 1024 && unitIndex < units.size - 1) {
                size /= 1024
                unitIndex++
            }

            return "%.1f %s".format(size, units[unitIndex])
        }
    }
}
