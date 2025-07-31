package com.runanywhere.runanywhereai.data.repository

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.runanywhere.runanywhereai.llm.LLMFramework
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import okhttp3.*
import java.io.*
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

/**
 * Enhanced model repository with update checking, differential downloads, and custom sources
 */
class ModelRepositoryEnhanced(private val context: Context) {
    companion object {
        private const val TAG = "ModelRepositoryEnhanced"
        private const val MODELS_DIR = "llm_models"
        private const val MODELS_METADATA_FILE = "models_metadata.json"
        private const val CUSTOM_SOURCES_FILE = "custom_sources.json"
        private const val UPDATE_CHECK_INTERVAL = 24 * 60 * 60 * 1000L // 24 hours
        private const val DIFFERENTIAL_CHUNK_SIZE = 1024 * 1024 // 1MB chunks
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    private val preferences: SharedPreferences = context.getSharedPreferences(
        "model_repository_prefs",
        Context.MODE_PRIVATE
    )

    private val modelsDirectory: File by lazy {
        File(context.filesDir, MODELS_DIR).apply {
            if (!exists()) mkdirs()
        }
    }

    private val metadataFile: File by lazy {
        File(modelsDirectory, MODELS_METADATA_FILE)
    }

    private val customSourcesFile: File by lazy {
        File(modelsDirectory, CUSTOM_SOURCES_FILE)
    }

    /**
     * Check for model updates from all sources
     */
    suspend fun checkForUpdates(): Flow<UpdateCheckResult> = flow {
        emit(UpdateCheckResult.Checking)

        try {
            val localMetadata = loadLocalMetadata()
            val customSources = loadCustomSources()
            val updatesFound = mutableListOf<ModelUpdateInfo>()

            // Check default sources
            val defaultUpdates = checkDefaultSourceUpdates(localMetadata)
            updatesFound.addAll(defaultUpdates)

            // Check custom sources
            for (source in customSources) {
                try {
                    val customUpdates = checkCustomSourceUpdates(source, localMetadata)
                    updatesFound.addAll(customUpdates)
                    emit(UpdateCheckResult.SourceChecked(source.name, customUpdates.size))
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to check updates from ${source.name}", e)
                    emit(UpdateCheckResult.SourceError(source.name, e.message ?: "Unknown error"))
                }
            }

            // Update last check timestamp
            preferences.edit()
                .putLong("last_update_check", System.currentTimeMillis())
                .apply()

            emit(UpdateCheckResult.Completed(updatesFound))

        } catch (e: Exception) {
            Log.e(TAG, "Failed to check for updates", e)
            emit(UpdateCheckResult.Error(e.message ?: "Unknown error"))
        }
    }

    /**
     * Download model with differential/resume support
     */
    suspend fun downloadModelWithResume(
        modelInfo: ModelInfo,
        customSource: CustomModelSource? = null
    ): Flow<DownloadProgress> = flow {
        val downloadUrl = customSource?.getDownloadUrl(modelInfo.id) ?: modelInfo.downloadUrl
        val modelFile = File(modelsDirectory, modelInfo.fileName)
        val tempFile = File(modelsDirectory, "${modelInfo.fileName}.tmp")

        try {
            emit(DownloadProgress.Starting)

            // Check if partial file exists (resume support)
            val existingBytes = if (tempFile.exists()) tempFile.length() else 0L
            val startTime = System.currentTimeMillis()

            val request = Request.Builder()
                .url(downloadUrl)
                .apply {
                    if (existingBytes > 0) {
                        addHeader("Range", "bytes=$existingBytes-")
                        Log.d(TAG, "Resuming download from byte $existingBytes")
                    }
                }
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("Download failed: ${response.code}")
                }

                val contentLength = response.header("Content-Length")?.toLongOrNull() ?: 0L
                val totalBytes = if (existingBytes > 0 && response.code == 206) {
                    // Partial content response
                    existingBytes + contentLength
                } else {
                    contentLength.takeIf { it > 0 } ?: modelInfo.sizeBytes
                }

                response.body?.let { responseBody ->
                    val inputStream = responseBody.byteStream()
                    val outputStream = FileOutputStream(tempFile, existingBytes > 0)

                    try {
                        val buffer = ByteArray(8192)
                        var downloadedBytes = existingBytes
                        var lastProgressUpdate = System.currentTimeMillis()
                        var lastDownloadedBytes = downloadedBytes

                        while (true) {
                            val bytesRead = inputStream.read(buffer)
                            if (bytesRead == -1) break

                            outputStream.write(buffer, 0, bytesRead)
                            downloadedBytes += bytesRead

                            val currentTime = System.currentTimeMillis()

                            // Update progress every 500ms
                            if (currentTime - lastProgressUpdate > 500) {
                                val timeDiff = currentTime - lastProgressUpdate
                                val bytesDiff = downloadedBytes - lastDownloadedBytes
                                val speed = if (timeDiff > 0) {
                                    (bytesDiff * 1000f / timeDiff).toLong()
                                } else null

                                emit(DownloadProgress.InProgress(
                                    progress = downloadedBytes.toFloat() / totalBytes,
                                    bytesDownloaded = downloadedBytes,
                                    totalBytes = totalBytes
                                ))

                                lastProgressUpdate = currentTime
                                lastDownloadedBytes = downloadedBytes
                            }
                        }

                        outputStream.flush()

                        // Verify download integrity
                        val downloadedHash = calculateFileHash(tempFile)
                        if (modelInfo.sha256Hash.isNotEmpty() && downloadedHash != modelInfo.sha256Hash) {
                            throw IOException("Downloaded file hash mismatch. Expected: ${modelInfo.sha256Hash}, Got: $downloadedHash")
                        }

                        // Move temp file to final location
                        if (!tempFile.renameTo(modelFile)) {
                            throw IOException("Failed to move downloaded file to final location")
                        }

                        // Update local metadata
                        updateLocalMetadata(modelInfo.copy(
                            isDownloaded = true,
                            localPath = modelFile.absolutePath,
                            downloadedAt = System.currentTimeMillis(),
                            sha256Hash = downloadedHash
                        ))

                        emit(DownloadProgress.Completed(modelFile.absolutePath))

                    } finally {
                        inputStream.close()
                        outputStream.close()
                    }
                } ?: throw IOException("Empty response body")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for model ${modelInfo.id}", e)

            // Clean up temp file on error
            if (tempFile.exists()) {
                tempFile.delete()
            }

            emit(DownloadProgress.Failed(e.message ?: "Download failed"))
        }
    }

    /**
     * Perform differential update for a model
     */
    suspend fun performDifferentialUpdate(
        modelInfo: ModelInfo,
        updateInfo: ModelUpdateInfo
    ): Flow<DownloadProgress> = flow {
        try {
            emit(DownloadProgress.Starting)

            val patchUrl = updateInfo.patchUrl
            if (patchUrl != null) {
                // Download and apply patch
                val patchFile = File(modelsDirectory, "${modelInfo.fileName}.patch")
                val updatedFile = File(modelsDirectory, "${modelInfo.fileName}.updated")

                // Download patch
                downloadPatch(patchUrl, patchFile, modelInfo.id) { progress ->
                    if (progress is DownloadProgress.InProgress) {
                        emit(DownloadProgress.InProgress(
                            progress = progress.progress * 0.7f,
                            bytesDownloaded = progress.bytesDownloaded,
                            totalBytes = progress.totalBytes
                        ))
                    } else {
                        emit(progress)
                    }
                }

                // Apply patch to existing file
                val existingFile = File(modelsDirectory, modelInfo.fileName)
                applyPatch(existingFile, patchFile, updatedFile, modelInfo.id) { progress ->
                    if (progress is DownloadProgress.InProgress) {
                        emit(DownloadProgress.InProgress(
                            progress = 0.7f + progress.progress * 0.3f,
                            bytesDownloaded = progress.bytesDownloaded,
                            totalBytes = progress.totalBytes
                        ))
                    } else {
                        emit(progress)
                    }
                }

                // Verify and replace
                val updatedHash = calculateFileHash(updatedFile)
                if (updatedHash == updateInfo.newSha256Hash) {
                    existingFile.delete()
                    updatedFile.renameTo(existingFile)

                    // Update metadata
                    updateLocalMetadata(modelInfo.copy(
                        version = updateInfo.newVersion,
                        sha256Hash = updatedHash,
                        lastModified = System.currentTimeMillis()
                    ))

                    emit(DownloadProgress.Completed(updatedFile.absolutePath))
                } else {
                    throw IOException("Patch verification failed")
                }

                // Cleanup
                patchFile.delete()
                updatedFile.delete()

            } else {
                // Fall back to full download
                downloadModelWithResume(modelInfo).collect { progress ->
                    emit(progress)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Differential update failed for model ${modelInfo.id}", e)
            emit(DownloadProgress.Failed(e.message ?: "Differential update failed"))
        }
    }

    /**
     * Add custom model source
     */
    suspend fun addCustomSource(source: CustomModelSource): Boolean = withContext(Dispatchers.IO) {
        try {
            val sources = loadCustomSources().toMutableList()

            // Validate source by attempting to fetch metadata
            val isValid = validateCustomSource(source)
            if (!isValid) {
                throw IllegalArgumentException("Invalid custom source: Unable to fetch model metadata")
            }

            // Add or update source
            val existingIndex = sources.indexOfFirst { it.id == source.id }
            if (existingIndex >= 0) {
                sources[existingIndex] = source
            } else {
                sources.add(source)
            }

            // Save updated sources
            saveCustomSources(sources)

            Log.d(TAG, "Added custom source: ${source.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add custom source", e)
            false
        }
    }

    /**
     * Remove custom model source
     */
    suspend fun removeCustomSource(sourceId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val sources = loadCustomSources().toMutableList()
            val removed = sources.removeAll { it.id == sourceId }

            if (removed) {
                saveCustomSources(sources)
                Log.d(TAG, "Removed custom source: $sourceId")
            }

            removed
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove custom source", e)
            false
        }
    }

    /**
     * Get all custom sources
     */
    suspend fun getCustomSources(): List<CustomModelSource> = withContext(Dispatchers.IO) {
        loadCustomSources()
    }

    // Private helper methods

    private suspend fun checkDefaultSourceUpdates(localMetadata: List<ModelMetadata>): List<ModelUpdateInfo> {
        // Implementation for checking default source updates
        // This would typically involve fetching from a central registry
        return emptyList() // Placeholder
    }

    private suspend fun checkCustomSourceUpdates(
        source: CustomModelSource,
        localMetadata: List<ModelMetadata>
    ): List<ModelUpdateInfo> {
        val updates = mutableListOf<ModelUpdateInfo>()

        try {
            val request = Request.Builder()
                .url(source.metadataUrl)
                .addHeader("User-Agent", "RunAnywhereAI-Android/1.0")
                .build()

            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val jsonData = response.body?.string() ?: return emptyList()
                    val sourceMetadata = json.decodeFromString<SourceMetadata>(jsonData)

                    for (remoteModel in sourceMetadata.models) {
                        val localModel = localMetadata.find { it.id == remoteModel.id }

                        if (localModel == null || shouldUpdateModel(localModel, remoteModel)) {
                            updates.add(ModelUpdateInfo(
                                modelId = remoteModel.id,
                                currentVersion = localModel?.version ?: "0.0.0",
                                newVersion = remoteModel.version,
                                newSha256Hash = remoteModel.sha256Hash,
                                patchUrl = remoteModel.patchUrl,
                                patchSizeBytes = remoteModel.patchSizeBytes,
                                fullDownloadUrl = remoteModel.downloadUrl,
                                releaseNotes = remoteModel.releaseNotes
                            ))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check updates from source ${source.name}", e)
        }

        return updates
    }

    private fun shouldUpdateModel(local: ModelMetadata, remote: RemoteModelMetadata): Boolean {
        // Simple version comparison - in production, use proper semantic versioning
        return remote.version > local.version ||
               remote.sha256Hash != local.sha256Hash ||
               (System.currentTimeMillis() - local.lastModified) > UPDATE_CHECK_INTERVAL
    }

    private suspend fun downloadPatch(
        patchUrl: String,
        patchFile: File,
        modelId: String,
        onProgress: suspend (DownloadProgress) -> Unit
    ) {
        val request = Request.Builder().url(patchUrl).build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Patch download failed: ${response.code}")
            }

            response.body?.let { body ->
                val contentLength = body.contentLength()
                val inputStream = body.byteStream()
                val outputStream = FileOutputStream(patchFile)

                try {
                    val buffer = ByteArray(8192)
                    var downloadedBytes = 0L
                    var lastProgressUpdate = System.currentTimeMillis()

                    while (true) {
                        val bytesRead = inputStream.read(buffer)
                        if (bytesRead == -1) break

                        outputStream.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead

                        val currentTime = System.currentTimeMillis()
                        if (currentTime - lastProgressUpdate > 500) {
                            onProgress(DownloadProgress(
                                modelId = modelId,
                                progress = if (contentLength > 0) downloadedBytes.toFloat() / contentLength else 0f,
                                downloadedBytes = downloadedBytes,
                                totalBytes = contentLength,
                                speedBytesPerSecond = null,
                                isCompleted = false
                            ))
                            lastProgressUpdate = currentTime
                        }
                    }
                } finally {
                    inputStream.close()
                    outputStream.close()
                }
            }
        }
    }

    private suspend fun applyPatch(
        originalFile: File,
        patchFile: File,
        outputFile: File,
        modelId: String,
        onProgress: suspend (DownloadProgress) -> Unit
    ) {
        // Placeholder for patch application logic
        // In a real implementation, this would use a binary diff library like bsdiff

        // For now, simulate patch application
        val originalSize = originalFile.length()
        val patchSize = patchFile.length()

        originalFile.copyTo(outputFile, overwrite = true)

        // Simulate progress
        for (i in 0..100 step 10) {
            onProgress(DownloadProgress(
                modelId = modelId,
                progress = i / 100f,
                downloadedBytes = (originalSize * i / 100).toLong(),
                totalBytes = originalSize,
                speedBytesPerSecond = null,
                isCompleted = false
            ))
            kotlinx.coroutines.delay(50) // Simulate work
        }
    }

    private suspend fun validateCustomSource(source: CustomModelSource): Boolean {
        return try {
            val request = Request.Builder()
                .url(source.metadataUrl)
                .build()

            client.newCall(request).execute().use { response ->
                response.isSuccessful && response.body != null
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun loadLocalMetadata(): List<ModelMetadata> {
        return try {
            if (metadataFile.exists()) {
                val jsonData = metadataFile.readText()
                json.decodeFromString<List<ModelMetadata>>(jsonData)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load local metadata", e)
            emptyList()
        }
    }

    private fun updateLocalMetadata(modelInfo: ModelInfo) {
        try {
            val metadata = loadLocalMetadata().toMutableList()
            val existingIndex = metadata.indexOfFirst { it.id == modelInfo.id }

            val newMetadata = ModelMetadata(
                id = modelInfo.id,
                version = modelInfo.version ?: "1.0.0",
                sha256Hash = modelInfo.sha256Hash,
                lastModified = System.currentTimeMillis(),
                localPath = modelInfo.localPath,
                downloadedAt = modelInfo.downloadedAt ?: System.currentTimeMillis()
            )

            if (existingIndex >= 0) {
                metadata[existingIndex] = newMetadata
            } else {
                metadata.add(newMetadata)
            }

            val jsonData = json.encodeToString(metadata)
            metadataFile.writeText(jsonData)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to update local metadata", e)
        }
    }

    private fun loadCustomSources(): List<CustomModelSource> {
        return try {
            if (customSourcesFile.exists()) {
                val jsonData = customSourcesFile.readText()
                json.decodeFromString<List<CustomModelSource>>(jsonData)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load custom sources", e)
            emptyList()
        }
    }

    private fun saveCustomSources(sources: List<CustomModelSource>) {
        try {
            val jsonData = json.encodeToString(sources)
            customSourcesFile.writeText(jsonData)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save custom sources", e)
        }
    }

    private fun calculateFileHash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(8192)

        file.inputStream().use { inputStream ->
            while (true) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead == -1) break
                digest.update(buffer, 0, bytesRead)
            }
        }

        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

// Data classes for enhanced functionality

@Serializable
data class ModelMetadata(
    val id: String,
    val version: String,
    val sha256Hash: String,
    val lastModified: Long,
    val localPath: String? = null,
    val downloadedAt: Long? = null
)

@Serializable
data class CustomModelSource(
    val id: String,
    val name: String,
    val description: String,
    val metadataUrl: String,
    val baseUrl: String,
    val requiresAuth: Boolean = false,
    val authToken: String? = null
) {
    fun getDownloadUrl(modelId: String): String {
        return "$baseUrl/models/$modelId/download"
    }
}

@Serializable
data class SourceMetadata(
    val name: String,
    val version: String,
    val models: List<RemoteModelMetadata>
)

@Serializable
data class RemoteModelMetadata(
    val id: String,
    val name: String,
    val version: String,
    val sha256Hash: String,
    val downloadUrl: String,
    val patchUrl: String? = null,
    val patchSizeBytes: Long? = null,
    val releaseNotes: String? = null
)

@Serializable
data class ModelUpdateInfo(
    val modelId: String,
    val currentVersion: String,
    val newVersion: String,
    val newSha256Hash: String,
    val patchUrl: String? = null,
    val patchSizeBytes: Long? = null,
    val fullDownloadUrl: String,
    val releaseNotes: String? = null
)

sealed class UpdateCheckResult {
    object Checking : UpdateCheckResult()
    data class SourceChecked(val sourceName: String, val updatesFound: Int) : UpdateCheckResult()
    data class SourceError(val sourceName: String, val error: String) : UpdateCheckResult()
    data class Completed(val updates: List<ModelUpdateInfo>) : UpdateCheckResult()
    data class Error(val message: String) : UpdateCheckResult()
}

// Extensions to existing ModelInfo
val ModelInfo.version: String?
    get() = null // This would be added to the original ModelInfo class

val ModelInfo.localPath: String?
    get() = null // This would be added to the original ModelInfo class

val ModelInfo.downloadedAt: Long?
    get() = null // This would be added to the original ModelInfo class
