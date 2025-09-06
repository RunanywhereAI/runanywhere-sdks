package com.runanywhere.sdk.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.network.HttpClient
import com.runanywhere.sdk.storage.FileSystem

/**
 * Common implementation of download service with HTTP downloading
 * Provides model downloading with progress tracking and validation
 */
class DownloadService(
    private val httpClient: HttpClient,
    private val fileSystem: FileSystem,
    private val validationService: ValidationService
) {
    private val logger = SDKLogger("DownloadService")

    companion object {
        private const val CHUNK_SIZE = 8192
    }

    /**
     * Download a model with progress tracking
     */
    suspend fun downloadModel(
        model: ModelInfo,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): String {
        try {
            val downloadURL = model.downloadURL
                ?: throw IllegalArgumentException("No download URL for model: ${model.id}")

            logger.info("Starting download of ${model.name} (${model.id}) from $downloadURL")

            // Check if file already exists and is valid
            if (fileSystem.exists(destinationPath)) {
                val existingSize = fileSystem.fileSize(destinationPath)
                val expectedSize = model.downloadSize ?: 0L

                if (existingSize > 0 && existingSize == expectedSize) {
                    logger.info("Model ${model.id} already exists with correct size")

                    // Validate the existing file
                    val validationResult = validationService.validateModel(model, destinationPath)
                    if (validationResult.isValid) {
                        onProgress(1.0f)
                        return destinationPath
                    } else {
                        logger.info("Existing model file is invalid. Re-downloading...")
                        fileSystem.delete(destinationPath)
                    }
                } else {
                    logger.info("Existing model file has incorrect size. Re-downloading...")
                    fileSystem.delete(destinationPath)
                }
            }

            // Ensure parent directory exists
            val parentPath = destinationPath.substringBeforeLast('/')
            if (parentPath.isNotEmpty()) {
                fileSystem.createDirectory(parentPath)
            }

            // Download the model
            logger.info("Downloading model from $downloadURL to $destinationPath")
            val data = httpClient.download(
                url = downloadURL,
                onProgress = { downloaded, total ->
                    if (total > 0) {
                        val progress = (downloaded.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                        onProgress(progress)

                        // Log progress every 10MB
                        if (downloaded % (10 * 1024 * 1024) == 0L) {
                            logger.info("Download progress: ${(progress * 100).toInt()}% (${downloaded / 1024 / 1024}MB)")
                        }
                    }
                }
            )

            // Save the downloaded data
            fileSystem.writeBytes(destinationPath, data)

            // Validate downloaded file
            val validationResult = validationService.validateModel(model, destinationPath)
            if (!validationResult.isValid) {
                // Clean up invalid file
                fileSystem.delete(destinationPath)
                throw IllegalStateException("Downloaded file validation failed: ${(validationResult as? ValidationService.ValidationResult.Invalid)?.reason}")
            }

            logger.info("Download completed successfully for model: ${model.id}")
            return destinationPath

        } catch (e: Exception) {
            logger.error("Download failed for model: ${model.id}", e)

            // Cleanup partial download
            if (fileSystem.exists(destinationPath)) {
                fileSystem.delete(destinationPath)
                logger.info("Cleaned up partial download")
            }

            throw e
        }
    }

    /**
     * Check if a URL is accessible
     */
    suspend fun checkUrlAccessibility(urlString: String): Boolean {
        return try {
            val response = httpClient.get(urlString)
            response.isSuccessful
        } catch (e: Exception) {
            logger.warn("URL accessibility check failed for $urlString: ${e.message}")
            false
        }
    }

    /**
     * Get content length without downloading
     */
    suspend fun getContentLength(urlString: String): Long {
        return try {
            val response = httpClient.get(
                url = urlString,
                headers = mapOf("Range" to "bytes=0-0") // Request only first byte to get content length
            )

            // Try to get content-range header which contains total size
            val contentRange = response.headers["Content-Range"]?.firstOrNull()
            if (contentRange != null && contentRange.contains("/")) {
                contentRange.substringAfterLast("/").toLongOrNull() ?: -1L
            } else {
                // Fall back to content-length
                response.headers["Content-Length"]?.firstOrNull()?.toLongOrNull() ?: -1L
            }
        } catch (e: Exception) {
            logger.warn("Failed to get content length for $urlString: ${e.message}")
            -1L
        }
    }

    /**
     * Resume a partial download
     */
    suspend fun resumeDownload(
        url: String,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): String {
        val existingSize = if (fileSystem.exists(destinationPath)) {
            fileSystem.fileSize(destinationPath)
        } else {
            0L
        }

        if (existingSize > 0) {
            logger.info("Resuming download from byte $existingSize")

            // Get the remaining data with Range header
            val remainingData = httpClient.download(
                url = url,
                headers = mapOf("Range" to "bytes=$existingSize-"),
                onProgress = { downloaded, total ->
                    val totalSize = existingSize + total
                    val currentProgress =
                        (existingSize + downloaded).toFloat() / totalSize.toFloat()
                    onProgress(currentProgress.coerceIn(0f, 1f))
                }
            )

            // Append to existing file
            val existingData = fileSystem.readBytes(destinationPath)
            val completeData = existingData + remainingData
            fileSystem.writeBytes(destinationPath, completeData)

            logger.info("Resume download completed")
        } else {
            // No existing file, do normal download
            val data = httpClient.download(
                url = url,
                onProgress = { downloaded, total ->
                    if (total > 0) {
                        val progress = (downloaded.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                        onProgress(progress)
                    }
                }
            )
            fileSystem.writeBytes(destinationPath, data)
        }

        return destinationPath
    }
}
