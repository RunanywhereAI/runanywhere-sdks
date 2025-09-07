package com.runanywhere.whisperkit.storage

import android.content.Context
import com.runanywhere.whisperkit.models.WhisperModelInfo
import com.runanywhere.whisperkit.models.WhisperModelType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URL

/**
 * Android implementation of WhisperStorageStrategy
 * Manages model storage and downloads for Android environments
 */
actual class DefaultWhisperStorage(
    private val context: Context
) : WhisperStorageStrategy {

    private val modelsDir: File by lazy {
        val dir = File(context.filesDir, "whisper/models")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        dir
    }

    override suspend fun getModelsDirectory(): String = withContext(Dispatchers.IO) {
        modelsDir.absolutePath
    }

    override suspend fun getModelPath(type: WhisperModelType): String = withContext(Dispatchers.IO) {
        File(modelsDir, type.fileName).absolutePath
    }

    override suspend fun isModelDownloaded(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
        File(modelsDir, type.fileName).exists()
    }

    override suspend fun getModelInfo(type: WhisperModelType): WhisperModelInfo = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        WhisperModelInfo(
            type = type,
            localPath = if (modelFile.exists()) modelFile.absolutePath else null,
            isDownloaded = modelFile.exists(),
            downloadProgress = if (modelFile.exists()) 1.0f else 0.0f,
            lastUsed = if (modelFile.exists()) modelFile.lastModified() else null
        )
    }

    override suspend fun getAllModels(): List<WhisperModelInfo> = withContext(Dispatchers.IO) {
        WhisperModelType.values().map { getModelInfo(it) }
    }

    override suspend fun downloadModel(
        type: WhisperModelType,
        onProgress: (Float) -> Unit
    ): String = withContext(Dispatchers.IO) {

        val modelFile = File(modelsDir, type.fileName)

        // Check if already downloaded
        if (modelFile.exists()) {
            onProgress(1.0f)
            return@withContext modelFile.absolutePath
        }

        try {
            // Create temp file for download
            val tempFile = File(modelsDir, "${type.fileName}.tmp")

            // Download the model
            val url = URL(type.downloadUrl)
            val connection = url.openConnection()
            val totalSize = connection.contentLengthLong

            connection.getInputStream().use { input ->
                tempFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalBytesRead = 0L

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead

                        if (totalSize > 0) {
                            val progress = totalBytesRead.toFloat() / totalSize.toFloat()
                            onProgress(progress)
                        }
                    }
                }
            }

            // Move temp file to final location
            tempFile.renameTo(modelFile)

            onProgress(1.0f)
            modelFile.absolutePath

        } catch (e: Exception) {
            // Clean up temp file if exists
            val tempFile = File(modelsDir, "${type.fileName}.tmp")
            if (tempFile.exists()) {
                tempFile.delete()
            }
            throw com.runanywhere.whisperkit.models.WhisperError.ModelDownloadFailed(
                "Failed to download model ${type.modelName}: ${e.message}"
            )
        }
    }

    override suspend fun deleteModel(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
        val modelFile = File(modelsDir, type.fileName)
        modelFile.delete()
    }

    override suspend fun getTotalStorageUsed(): Long = withContext(Dispatchers.IO) {
        modelsDir.listFiles()?.sumOf { it.length() } ?: 0L
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
        }
    }
}
