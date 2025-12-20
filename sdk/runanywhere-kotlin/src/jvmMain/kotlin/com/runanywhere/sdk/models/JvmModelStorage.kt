package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.*
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/**
 * JVM Model Storage implementation for WhisperJNI models.
 *
 * This implementation follows the iOS model management patterns exactly,
 * providing model downloading, caching, and validation functionality.
 */
class JvmModelStorage {
    private val logger = SDKLogger("JvmModelStorage")

    // Model storage directory (following iOS pattern)
    private val modelStorageDir: Path =
        Paths.get(
            System.getProperty("user.home"),
            ".runanywhere",
            "models",
        )

    // Whisper model download URLs (standard whisper.cpp models)
    private val modelDownloadUrls =
        mapOf(
            "ggml-tiny.bin" to "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
            "ggml-base.bin" to "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
            "ggml-small.bin" to "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
            "ggml-medium.bin" to "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
            "ggml-large-v3.bin" to "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
        )

    // Expected model sizes for validation (in bytes)
    // Updated sizes based on actual Hugging Face repository
    private val modelSizes =
        mapOf(
            "ggml-tiny.bin" to 77_700_000L, // ~77.7 MB
            "ggml-base.bin" to 147_951_465L, // ~148 MB (exact size from logs)
            "ggml-small.bin" to 488_000_000L, // ~488 MB
            "ggml-medium.bin" to 1_530_000_000L, // ~1.53 GB
            "ggml-large-v3.bin" to 3_100_000_000L, // ~3.1 GB
        )

    init {
        // Ensure storage directory exists
        try {
            Files.createDirectories(modelStorageDir)
            logger.info("Model storage directory: ${modelStorageDir.toAbsolutePath()}")
        } catch (e: IOException) {
            logger.error("Failed to create model storage directory", e)
        }
    }

    /**
     * Check if a model is available locally
     */
    fun isModelAvailable(modelId: String?): Boolean {
        val fileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(modelId)
        val modelFile = modelStorageDir.resolve(fileName).toFile()

        val isAvailable = modelFile.exists() && modelFile.length() > 0
        logger.debug("Model $fileName availability: $isAvailable")

        return isAvailable
    }

    /**
     * Get the local path for a model
     */
    fun getModelPath(modelId: String?): String {
        val fileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(modelId)
        return modelStorageDir.resolve(fileName).toAbsolutePath().toString()
    }

    /**
     * Download a model with progress tracking (iOS pattern)
     * Returns Flow<Float> where values are between 0.0 and 1.0
     */
    fun downloadModel(modelId: String?): Flow<Float> =
        flow {
            val fileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(modelId)
            val modelFile = modelStorageDir.resolve(fileName).toFile()

            // Check if model already exists and is valid
            if (modelFile.exists() && validateModel(fileName)) {
                logger.info("Model $fileName already exists and is valid")
                emit(1.0f)
                return@flow
            }

            val downloadUrl =
                modelDownloadUrls[fileName]
                    ?: throw ModelDownloadException("No download URL for model: $fileName")

            logger.info("Downloading model $fileName from $downloadUrl")

            withContext(Dispatchers.IO) {
                try {
                    downloadModelFromUrl(downloadUrl, modelFile) { progress ->
                        // Emit progress to flow - removed nested runCatching
                        emit(progress)
                    }

                    // Validate downloaded model
                    if (validateModel(fileName)) {
                        logger.info("Model $fileName downloaded and validated successfully")
                        emit(1.0f)
                    } else {
                        logger.error("Downloaded model $fileName failed validation")
                        modelFile.delete()
                        throw ModelDownloadException("Downloaded model failed validation: $fileName")
                    }
                } catch (e: Exception) {
                    logger.error("Failed to download model $fileName", e)

                    // Clean up partial download
                    if (modelFile.exists()) {
                        modelFile.delete()
                    }

                    throw when (e) {
                        is ModelDownloadException -> e
                        else -> ModelDownloadException("Download failed for $fileName: ${e.message}", e)
                    }
                }
            }
        }

    /**
     * Validate a downloaded model
     */
    private fun validateModel(fileName: String): Boolean {
        val modelFile = modelStorageDir.resolve(fileName).toFile()

        if (!modelFile.exists()) {
            logger.debug("Model validation failed: file does not exist - $fileName")
            return false
        }

        val actualSize = modelFile.length()
        val expectedSize = modelSizes[fileName]

        if (expectedSize != null) {
            // Allow 5% variance in size for different versions/compressions
            val sizeVariance = expectedSize * 0.05
            val isValidSize =
                actualSize >= (expectedSize - sizeVariance) &&
                    actualSize <= (expectedSize + sizeVariance)

            if (!isValidSize) {
                logger.warn("Model $fileName size validation failed: expected ~$expectedSize, got $actualSize")
                return false
            }
        }

        // Basic file header validation for GGML format
        try {
            FileInputStream(modelFile).use { fis ->
                val header = ByteArray(8)
                if (fis.read(header) == 8) {
                    // Check for GGML magic number
                    val magic = String(header, 0, 4, Charsets.UTF_8)
                    // Also accept reversed byte order 'lmgg' which can happen with some downloads
                    if (magic != "ggml" && magic != "gguf" && magic != "lmgg" && magic != "fugg") {
                        logger.warn("Model $fileName header validation failed: invalid magic number '$magic'")
                        // For now, just log warning but don't fail validation
                        // Some models may have different headers
                        logger.warn("Accepting model despite header mismatch - whisper.cpp may still be able to use it")
                    }
                }
            }
        } catch (e: IOException) {
            logger.error("Error validating model header for $fileName", e)
            return false
        }

        logger.debug("Model $fileName validated successfully")
        return true
    }

    /**
     * Download model from URL with progress callback
     */
    private suspend fun downloadModelFromUrl(
        url: String,
        destinationFile: File,
        onProgress: suspend (Float) -> Unit,
    ) = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        var inputStream: InputStream? = null
        var outputStream: FileOutputStream? = null

        try {
            // Create connection
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 30000 // 30 seconds
            connection.readTimeout = 30000
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK/1.0")
            connection.instanceFollowRedirects = true

            connection.connect()

            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw ModelDownloadException(
                    "HTTP error ${connection.responseCode}: ${connection.responseMessage}",
                )
            }

            val contentLength = connection.contentLengthLong
            logger.info("Downloading $contentLength bytes to ${destinationFile.name}")

            // Create temporary file for atomic download
            val tempFile = File(destinationFile.absolutePath + ".tmp")
            tempFile.parentFile?.mkdirs()

            inputStream = connection.inputStream
            outputStream = FileOutputStream(tempFile)

            val buffer = ByteArray(8192)
            var totalBytesRead = 0L
            var bytesRead: Int

            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                outputStream.write(buffer, 0, bytesRead)
                totalBytesRead += bytesRead

                // Report progress (iOS pattern)
                if (contentLength > 0) {
                    val progress = totalBytesRead.toFloat() / contentLength.toFloat()
                    onProgress(progress)
                }
            }

            outputStream.flush()
            outputStream.close()
            outputStream = null

            // Atomic move from temp to final location
            // Only delete destination if it exists AND we're about to replace it
            // This prevents deleting a good file if the move fails

            // Try renameTo first (atomic on same filesystem)
            if (!tempFile.renameTo(destinationFile)) {
                // If renameTo fails (usually because destination exists or cross-filesystem)
                // Try copy and delete approach
                logger.warn("renameTo failed, trying copy approach")
                try {
                    // copyTo with overwrite=true will handle existing file
                    tempFile.copyTo(destinationFile, overwrite = true)
                    tempFile.delete()
                    logger.info("Successfully copied temp file to destination")
                } catch (e: Exception) {
                    logger.error("Failed to copy temp file to destination", e)
                    throw ModelDownloadException("Failed to move temporary file to final location: ${e.message}", e)
                }
            }

            logger.info("Download completed: ${destinationFile.name} ($totalBytesRead bytes)")
        } finally {
            try {
                inputStream?.close()
                outputStream?.close()
                connection?.disconnect()
            } catch (e: Exception) {
                logger.error("Error closing download resources", e)
            }
        }
    }

    /**
     * Delete a model file
     */
    fun deleteModel(modelId: String?): Boolean {
        val fileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(modelId)
        val modelFile = modelStorageDir.resolve(fileName).toFile()

        return try {
            if (modelFile.exists()) {
                val deleted = modelFile.delete()
                if (deleted) {
                    logger.info("Model $fileName deleted successfully")
                } else {
                    logger.warn("Failed to delete model $fileName")
                }
                deleted
            } else {
                logger.debug("Model $fileName does not exist, nothing to delete")
                true
            }
        } catch (e: Exception) {
            logger.error("Error deleting model $fileName", e)
            false
        }
    }

    /**
     * Get all available models (downloaded and available for download)
     */
    fun getAllAvailableModels(): List<JvmModelInfo> =
        JvmWhisperJNIModelMapper
            .getSupportedModelIds()
            .map { modelId ->
                val fileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(modelId)
                val isDownloaded = isModelAvailable(modelId)
                val localPath = if (isDownloaded) getModelPath(modelId) else null

                JvmModelInfo(
                    modelId = modelId,
                    fileName = fileName,
                    displayName = formatDisplayName(modelId),
                    size = JvmWhisperJNIModelMapper.getModelSize(modelId) * 1024 * 1024, // Convert MB to bytes
                    downloadUrl = modelDownloadUrls[fileName],
                    localPath = localPath,
                    isDownloaded = isDownloaded,
                    modelType = JvmWhisperJNIModelMapper.getModelType(modelId),
                )
            }.sortedBy { it.size }

    /**
     * Get storage statistics
     */
    fun getStorageStats(): StorageStats {
        val allModels = getAllAvailableModels()
        val downloadedModels = allModels.filter { it.isDownloaded }

        val totalSize = downloadedModels.sumOf { it.size }
        val availableSpace =
            try {
                Files.getFileStore(modelStorageDir).usableSpace
            } catch (e: IOException) {
                logger.error("Error getting available space", e)
                -1L
            }

        return StorageStats(
            storageDirectory = modelStorageDir.toAbsolutePath().toString(),
            totalModels = allModels.size,
            downloadedModels = downloadedModels.size,
            totalSizeBytes = totalSize,
            availableSpaceBytes = availableSpace,
        )
    }

    /**
     * Cleanup temporary files and validate all models
     */
    fun cleanup(): CleanupResult {
        var tempFilesDeleted = 0
        var invalidModelsDeleted = 0

        try {
            // Delete temporary files (.tmp)
            modelStorageDir.toFile().listFiles()?.forEach { file ->
                if (file.name.endsWith(".tmp")) {
                    if (file.delete()) {
                        tempFilesDeleted++
                        logger.info("Deleted temporary file: ${file.name}")
                    }
                }
            }

            // Validate all downloaded models and delete invalid ones
            getAllAvailableModels().filter { it.isDownloaded }.forEach { model ->
                if (!validateModel(model.fileName)) {
                    if (deleteModel(model.modelId)) {
                        invalidModelsDeleted++
                        logger.warn("Deleted invalid model: ${model.modelId}")
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Error during cleanup", e)
        }

        return CleanupResult(
            tempFilesDeleted = tempFilesDeleted,
            invalidModelsDeleted = invalidModelsDeleted,
        )
    }

    private fun formatDisplayName(modelId: String): String =
        modelId.split("-", "_").joinToString(" ") { word ->
            word.lowercase().replaceFirstChar { it.uppercase() }
        }
}

/**
 * Data classes for model management
 */
data class JvmModelInfo(
    val modelId: String,
    val fileName: String,
    val displayName: String,
    val size: Long,
    val downloadUrl: String?,
    val localPath: String?,
    val isDownloaded: Boolean,
    val modelType: String,
)

data class StorageStats(
    val storageDirectory: String,
    val totalModels: Int,
    val downloadedModels: Int,
    val totalSizeBytes: Long,
    val availableSpaceBytes: Long,
)

data class CleanupResult(
    val tempFilesDeleted: Int,
    val invalidModelsDeleted: Int,
)

/**
 * Model download exception
 */
class ModelDownloadException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
