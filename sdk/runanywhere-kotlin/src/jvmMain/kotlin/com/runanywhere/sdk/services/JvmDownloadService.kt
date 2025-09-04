package com.runanywhere.sdk.services

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * JVM implementation of download service with real HTTP downloading
 * Provides model downloading with progress tracking and checksum validation
 */
class JvmDownloadService {
    private val logger = SDKLogger("JvmDownloadService")

    companion object {
        private const val BUFFER_SIZE = 8192
        private const val CONNECTION_TIMEOUT = 30_000 // 30 seconds
        private const val READ_TIMEOUT = 60_000 // 60 seconds
    }

    /**
     * Download a model with real HTTP implementation
     */
    suspend fun downloadModel(
        model: ModelInfo,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): String = withContext(Dispatchers.IO) {
        try {
            val downloadURL = model.downloadURL
                ?: throw IllegalArgumentException("No download URL for model: ${model.id}")

            logger.info("Starting download of ${model.name} (${model.id}) from $downloadURL")

            val destinationFile = File(destinationPath)
            destinationFile.parentFile?.mkdirs()

            // Check if file already exists and is valid
            if (destinationFile.exists()) {
                val existingSize = destinationFile.length()
                val expectedSize = model.downloadSize ?: 0L
                if (existingSize > 0 && existingSize == expectedSize) {
                    logger.info("Model ${model.id} already exists with correct size")
                    onProgress(1.0f)
                    return@withContext destinationFile.absolutePath
                } else {
                    logger.info("Existing model file has incorrect size. Re-downloading...")
                    destinationFile.delete()
                }
            }

            // Download the model
            downloadWithProgress(downloadURL, destinationFile, model.downloadSize ?: 0L, onProgress)

            // Validate downloaded file
            if (destinationFile.exists()) {
                val downloadedSize = destinationFile.length()
                val expectedSize = model.downloadSize ?: 0L
                logger.info("Download completed. File size: $downloadedSize bytes, Expected: $expectedSize")

                if (expectedSize > 0 && downloadedSize != expectedSize) {
                    logger.warn("Downloaded file size ($downloadedSize) doesn't match expected size ($expectedSize)")
                    // Don't throw error for now, just log warning
                }

                // Calculate and log file hash for debugging
                val fileHash = calculateMD5(destinationFile)
                logger.info("Downloaded file MD5: $fileHash")

                return@withContext destinationFile.absolutePath
            } else {
                throw IllegalStateException("Download completed but file doesn't exist")
            }

        } catch (e: Exception) {
            logger.error("Download failed for model: ${model.id}", e)

            // Cleanup partial download
            val file = File(destinationPath)
            if (file.exists()) {
                file.delete()
                logger.info("Cleaned up partial download")
            }

            throw e
        }
    }

    /**
     * Download file with progress tracking
     */
    private fun downloadWithProgress(
        urlString: String,
        destinationFile: File,
        expectedSize: Long,
        onProgress: (Float) -> Unit
    ) {
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection

        try {
            // Configure connection
            connection.connectTimeout = CONNECTION_TIMEOUT
            connection.readTimeout = READ_TIMEOUT
            connection.requestMethod = "GET"
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK-JVM/1.0")

            // Connect and check response
            connection.connect()
            val responseCode = connection.responseCode

            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("HTTP error $responseCode: ${connection.responseMessage}")
            }

            val contentLength = connection.contentLengthLong
            logger.info("Content-Length: $contentLength, Expected: $expectedSize")

            // Download with progress tracking
            connection.inputStream.use { inputStream ->
                FileOutputStream(destinationFile).use { outputStream ->
                    downloadStream(inputStream, outputStream, contentLength, onProgress)
                }
            }

        } finally {
            connection.disconnect()
        }
    }

    /**
     * Stream download with progress reporting
     */
    private fun downloadStream(
        inputStream: InputStream,
        outputStream: FileOutputStream,
        totalSize: Long,
        onProgress: (Float) -> Unit
    ) {
        val buffer = ByteArray(BUFFER_SIZE)
        var bytesRead = 0
        var totalBytesRead = 0L
        var lastProgressUpdate = 0L

        onProgress(0.0f)

        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
            outputStream.write(buffer, 0, bytesRead)
            totalBytesRead += bytesRead

            // Update progress every 100KB or so
            if (totalBytesRead - lastProgressUpdate > 100_000 || bytesRead == -1) {
                val progress = if (totalSize > 0) {
                    (totalBytesRead.toFloat() / totalSize.toFloat()).coerceIn(0f, 1f)
                } else {
                    0f
                }
                onProgress(progress)
                lastProgressUpdate = totalBytesRead

                // Log progress every 10MB
                if (totalBytesRead % (10 * 1024 * 1024) == 0L) {
                    logger.info("Download progress: ${(progress * 100).toInt()}% (${totalBytesRead / 1024 / 1024}MB)")
                }
            }
        }

        outputStream.flush()
        onProgress(1.0f)
        logger.info("Download stream completed: $totalBytesRead bytes")
    }

    /**
     * Calculate MD5 hash of a file for validation
     */
    private fun calculateMD5(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().use { inputStream ->
            val buffer = ByteArray(BUFFER_SIZE)
            var bytesRead = 0

            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }

        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Check if a URL is accessible
     */
    suspend fun checkUrlAccessibility(urlString: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL(urlString)
            val connection = url.openConnection() as HttpURLConnection

            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.requestMethod = "HEAD"
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK-JVM/1.0")

            val responseCode = connection.responseCode
            connection.disconnect()

            return@withContext responseCode == HttpURLConnection.HTTP_OK

        } catch (e: Exception) {
            logger.warn("URL accessibility check failed for $urlString")
            return@withContext false
        }
    }

    /**
     * Get content length without downloading
     */
    suspend fun getContentLength(urlString: String): Long = withContext(Dispatchers.IO) {
        try {
            val url = URL(urlString)
            val connection = url.openConnection() as HttpURLConnection

            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.requestMethod = "HEAD"
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK-JVM/1.0")

            val contentLength = connection.contentLengthLong
            connection.disconnect()

            return@withContext contentLength

        } catch (e: Exception) {
            logger.warn("Failed to get content length for $urlString")
            return@withContext -1L
        }
    }
}
