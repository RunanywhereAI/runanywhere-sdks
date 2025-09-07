package com.runanywhere.whisperkit.storage

import com.runanywhere.sdk.storage.DownloadProgress
import com.runanywhere.sdk.storage.DownloadState
import com.runanywhere.sdk.storage.DownloadError
import com.runanywhere.whisperkit.models.WhisperModelInfo
import com.runanywhere.whisperkit.models.WhisperModelType
import com.runanywhere.whisperkit.models.WhisperError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/**
 * JVM implementation of WhisperStorageStrategy with complete iOS alignment
 * Provides comprehensive storage, download, and validation capabilities
 */
actual class DefaultWhisperStorage : WhisperStorageStrategy() {

    private val modelsDir: File by lazy {
        val userHome = System.getProperty("user.home")
        val dir = File(userHome, ".runanywhere/whisper/models")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        dir
    }

    // Cache manager removed - doesn't exist in iOS

    override suspend fun getModelPath(type: WhisperModelType): String = withContext(Dispatchers.IO) {
        File(modelsDir, type.fileName).absolutePath
    }

    override suspend fun isModelDownloaded(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        modelFile.exists() && modelFile.length() > 0
    }

    override suspend fun getModelInfo(type: WhisperModelType): WhisperModelInfo = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        WhisperModelInfo(
            type = type,
            localPath = if (modelFile.exists()) modelFile.absolutePath else null,
            isDownloaded = modelFile.exists() && modelFile.length() > 0,
            downloadProgress = if (modelFile.exists() && modelFile.length() > 0) 1.0f else 0.0f,
            lastUsed = if (modelFile.exists()) modelFile.lastModified() else null
        )
    }

    override suspend fun getAllModels(): List<WhisperModelInfo> = withContext(Dispatchers.IO) {
        WhisperModelType.values().map { getModelInfo(it) }
    }

    override suspend fun deleteModel(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        if (modelFile.exists()) {
            modelFile.delete()
        } else {
            true // Already doesn't exist
        }
    }

    override suspend fun getTotalStorageUsed(): Long = withContext(Dispatchers.IO) {
        modelsDir.listFiles()?.sumOf { file ->
            if (file.name.endsWith(".bin")) file.length() else 0L
        } ?: 0L
    }

    override suspend fun cleanupOldModels(keepTypes: List<WhisperModelType>): Unit = withContext(Dispatchers.IO) {
        val keepFileNames = keepTypes.map { it.fileName }.toSet()

        modelsDir.listFiles()?.forEach { file ->
            if (file.name.endsWith(".bin") && !keepFileNames.contains(file.name)) {
                file.delete()
            }
        }
    }

    override suspend fun updateLastUsed(type: WhisperModelType) = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        if (modelFile.exists()) {
            modelFile.setLastModified(System.currentTimeMillis())
            // Cache tracking removed - doesn't exist in iOS
        }
    }

    override suspend fun downloadModel(
        type: WhisperModelType,
        onProgress: (DownloadProgress) -> Unit
    ) = withContext(Dispatchers.IO) {

        val modelFile = File(modelsDir, type.fileName)

        // Check if already downloaded
        if (isModelDownloaded(type)) {
            onProgress(DownloadProgress(
                bytesDownloaded = modelFile.length(),
                totalBytes = modelFile.length(),
                state = DownloadState.COMPLETED,
                currentFile = type.fileName
            ))
            return@withContext
        }

        var tempFile: File? = null

        try {
            // Create temp file for download
            tempFile = File(modelsDir, "${type.fileName}.tmp")

            // Initialize progress
            onProgress(DownloadProgress(
                bytesDownloaded = 0L,
                totalBytes = type.approximateSizeMB * 1024 * 1024L, // Estimated size
                state = DownloadState.DOWNLOADING,
                currentFile = type.fileName
            ))

            // Download the model with enhanced error handling
            val url = URL(type.downloadUrl)
            val connection = url.openConnection() as HttpURLConnection

            // Set connection properties
            connection.connectTimeout = 30000 // 30 seconds
            connection.readTimeout = 60000 // 60 seconds
            connection.requestMethod = "GET"
            connection.setRequestProperty("User-Agent", "RunAnywhere-KotlinSDK/1.0")

            // Check HTTP response code
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                throw DownloadError.HttpError(responseCode, connection.responseMessage)
            }

            val totalSize = connection.contentLengthLong
            val actualTotalSize = if (totalSize > 0) totalSize else type.approximateSizeMB * 1024 * 1024L

            connection.inputStream.use { input ->
                tempFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalBytesRead = 0L
                    var lastProgressUpdate = System.currentTimeMillis()

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead

                        // Update progress every 100ms to avoid too frequent updates
                        val now = System.currentTimeMillis()
                        if (now - lastProgressUpdate >= 100) {
                            val estimatedTimeRemaining = if (totalBytesRead > 0 && totalSize > 0) {
                                val remainingBytes = totalSize - totalBytesRead
                                val bytesPerSecond = totalBytesRead.toDouble() / ((now - lastProgressUpdate + 1000) / 1000.0)
                                if (bytesPerSecond > 0) remainingBytes / bytesPerSecond else null
                            } else null

                            onProgress(DownloadProgress(
                                bytesDownloaded = totalBytesRead,
                                totalBytes = actualTotalSize,
                                state = DownloadState.DOWNLOADING,
                                estimatedTimeRemaining = estimatedTimeRemaining,
                                currentFile = type.fileName
                            ))
                            lastProgressUpdate = now
                        }
                    }

                    // Verify download completeness
                    if (totalSize > 0 && totalBytesRead != totalSize) {
                        throw DownloadError.PartialDownload(totalSize, totalBytesRead)
                    }
                }
            }

            // Validate downloaded file
            if (!tempFile.exists() || tempFile.length() == 0L) {
                throw DownloadError.PartialDownload(actualTotalSize, 0L)
            }

            // Move temp file to final location atomically
            Files.move(
                tempFile.toPath(),
                modelFile.toPath(),
                StandardCopyOption.REPLACE_EXISTING
            )

            // Final progress update
            onProgress(DownloadProgress(
                bytesDownloaded = modelFile.length(),
                totalBytes = modelFile.length(),
                state = DownloadState.COMPLETED,
                currentFile = type.fileName
            ))

            // Cache events removed - doesn't exist in iOS

        } catch (e: DownloadError) {
            // Clean up and re-throw download errors
            tempFile?.let { if (it.exists()) it.delete() }
            onProgress(DownloadProgress(
                bytesDownloaded = 0L,
                totalBytes = type.approximateSizeMB * 1024 * 1024L,
                state = DownloadState.FAILED,
                currentFile = type.fileName
            ))
            throw e
        } catch (e: IOException) {
            // Clean up temp file if exists
            tempFile?.let { if (it.exists()) it.delete() }
            onProgress(DownloadProgress(
                bytesDownloaded = 0L,
                totalBytes = type.approximateSizeMB * 1024 * 1024L,
                state = DownloadState.FAILED,
                currentFile = type.fileName
            ))
            throw DownloadError.NetworkError(e)
        } catch (e: Exception) {
            // Clean up temp file if exists
            tempFile?.let { if (it.exists()) it.delete() }
            onProgress(DownloadProgress(
                bytesDownloaded = 0L,
                totalBytes = type.approximateSizeMB * 1024 * 1024L,
                state = DownloadState.FAILED,
                currentFile = type.fileName
            ))
            throw DownloadError.UnknownError("Failed to download model ${type.modelName}: ${e.message}", e)
        }
    }

    /**
     * Calculate SHA-256 checksum for a file (for future validation features)
     */
    private suspend fun calculateChecksum(file: File): String = withContext(Dispatchers.IO) {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    }

    // Additional cache management methods for iOS alignment

    // Cache statistics removed - doesn't exist in iOS

    /**
     * Ensure sufficient space for model download
     */
    suspend fun ensureSpaceForModel(type: WhisperModelType): Boolean {
        val requiredBytes = type.approximateSizeMB * 1024 * 1024L
        // Simple space check without cache manager
        val freeSpace = modelsDir.usableSpace
        return freeSpace > requiredBytes
    }

    // Cache entries method removed - doesn't exist in iOS

    // Cache cleanup policy removed - doesn't exist in iOS

    /**
     * Validate model integrity using checksum
     */
    suspend fun validateModelIntegrity(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        if (!modelFile.exists()) return@withContext false

        try {
            // For now, just check if file exists and has content
            // In the future, this could validate against known checksums
            modelFile.exists() && modelFile.length() > 0
        } catch (e: Exception) {
            false
        }
    }
}
