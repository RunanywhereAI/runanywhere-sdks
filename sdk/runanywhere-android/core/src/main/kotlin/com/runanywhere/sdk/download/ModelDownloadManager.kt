package com.runanywhere.sdk.download

import android.content.Context
import com.downloader.*
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.suspendCancellableCoroutine
import org.apache.commons.io.FileUtils
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Model Download Manager using PRDownloader - a battle-tested download library
 * Provides pause/resume support, progress tracking, and robust error handling
 */
class ModelDownloadManager(
    private val context: Context,
    private val repository: ModelInfoRepository
) {
    private val activeDownloads = ConcurrentHashMap<String, Int>() // taskId to downloadId
    private val downloadTasks = ConcurrentHashMap<String, DownloadTask>()

    init {
        // Initialize PRDownloader with configuration
        val config = PRDownloaderConfig.newBuilder()
            .setDatabaseEnabled(true) // Enable database for resume support
            .setReadTimeout(30_000) // 30 seconds
            .setConnectTimeout(30_000) // 30 seconds
            .build()

        PRDownloader.initialize(context, config)

        // Set maximum concurrent downloads
        PRDownloader.setMaxConcurrentDownloads(3)
    }

    /**
     * Download a model with full progress tracking and resume support
     */
    suspend fun downloadModel(model: ModelInfo): DownloadTask {
        val downloadUrl = model.downloadURL
            ?: throw DownloadException.InvalidURL("No download URL for model ${model.id}")

        val taskId = UUID.randomUUID().toString()
        val destinationDir = getModelDirectory(model)
        val destinationFile = File(destinationDir, "${model.id}.${model.format.value}")

        // Ensure directory exists
        destinationDir.mkdirs()

        // Create progress flow
        val progressFlow = callbackFlow<DownloadProgress> {
            var downloadId: Int = -1

            try {
                // Check if file partially exists for resume
                val headers = if (destinationFile.exists()) {
                    mapOf("Range" to "bytes=${destinationFile.length()}-")
                } else {
                    emptyMap()
                }

                downloadId = PRDownloader.download(
                    downloadUrl,
                    destinationDir.absolutePath,
                    destinationFile.name
                )
                    .setHeader(headers)
                    .build()
                    .setOnStartOrResumeListener {
                        trySend(
                            DownloadProgress(
                                bytesDownloaded = 0,
                                totalBytes = model.downloadSize ?: 0,
                                state = DownloadState.STARTED,
                                speedBytesPerSecond = 0
                            )
                        )
                    }
                    .setOnPauseListener {
                        trySend(
                            DownloadProgress(
                                bytesDownloaded = destinationFile.length(),
                                totalBytes = model.downloadSize ?: 0,
                                state = DownloadState.PAUSED,
                                speedBytesPerSecond = 0
                            )
                        )
                    }
                    .setOnCancelListener {
                        trySend(
                            DownloadProgress(
                                bytesDownloaded = 0,
                                totalBytes = model.downloadSize ?: 0,
                                state = DownloadState.CANCELLED,
                                speedBytesPerSecond = 0
                            )
                        )
                    }
                    .setOnProgressListener { progress ->
                        val currentBytes = progress.currentBytes
                        val totalBytes = progress.totalBytes

                        trySend(
                            DownloadProgress(
                                bytesDownloaded = currentBytes,
                                totalBytes = totalBytes,
                                state = DownloadState.DOWNLOADING,
                                speedBytesPerSecond = calculateSpeed(
                                    currentBytes,
                                    progress.currentBytes
                                )
                            )
                        )
                    }
                    .start(object : OnDownloadListener {
                        override fun onDownloadComplete() {
                            // Update model with local path
                            model.localPath = destinationFile.absolutePath

                            // Update repository
                            kotlinx.coroutines.runBlocking {
                                repository.updateDownloadStatus(
                                    model.id,
                                    destinationFile.absolutePath
                                )
                            }

                            trySend(
                                DownloadProgress(
                                    bytesDownloaded = model.downloadSize
                                        ?: destinationFile.length(),
                                    totalBytes = model.downloadSize ?: destinationFile.length(),
                                    state = DownloadState.COMPLETED,
                                    speedBytesPerSecond = 0
                                )
                            )

                            channel.close()
                        }

                        override fun onError(error: Error) {
                            val downloadError = when {
                                error.isConnectionError -> DownloadException.NetworkError(
                                    "Connection error: ${error.connectionException?.message}"
                                )

                                error.isServerError -> DownloadException.ServerError(
                                    error.serverErrorMessage ?: "Server error"
                                )

                                else -> DownloadException.Unknown(
                                    error.connectionException?.message ?: "Unknown error"
                                )
                            }

                            trySend(
                                DownloadProgress(
                                    bytesDownloaded = 0,
                                    totalBytes = model.downloadSize ?: 0,
                                    state = DownloadState.FAILED(downloadError),
                                    speedBytesPerSecond = 0
                                )
                            )

                            channel.close(downloadError)
                        }
                    })

                // Store download ID
                activeDownloads[taskId] = downloadId

            } catch (e: Exception) {
                val error = DownloadException.Unknown(e.message ?: "Failed to start download")
                trySend(
                    DownloadProgress(
                        bytesDownloaded = 0,
                        totalBytes = model.downloadSize ?: 0,
                        state = DownloadState.FAILED(error),
                        speedBytesPerSecond = 0
                    )
                )
                throw error
            }

            awaitClose {
                // Cleanup when flow is cancelled
                if (downloadId != -1) {
                    PRDownloader.cancel(downloadId)
                }
                activeDownloads.remove(taskId)
                downloadTasks.remove(taskId)
            }
        }

        val task = DownloadTask(
            id = taskId,
            modelId = model.id,
            modelInfo = model,
            progress = progressFlow
        )

        downloadTasks[taskId] = task
        return task
    }

    /**
     * Pause a download
     */
    fun pauseDownload(taskId: String) {
        activeDownloads[taskId]?.let { downloadId ->
            PRDownloader.pause(downloadId)
        }
    }

    /**
     * Resume a paused download
     */
    fun resumeDownload(taskId: String) {
        activeDownloads[taskId]?.let { downloadId ->
            PRDownloader.resume(downloadId)
        }
    }

    /**
     * Cancel a download
     */
    fun cancelDownload(taskId: String) {
        activeDownloads[taskId]?.let { downloadId ->
            PRDownloader.cancel(downloadId)
            activeDownloads.remove(taskId)
            downloadTasks.remove(taskId)
        }
    }

    /**
     * Cancel all downloads
     */
    fun cancelAll() {
        PRDownloader.cancelAll()
        activeDownloads.clear()
        downloadTasks.clear()
    }

    /**
     * Pause all downloads
     */
    fun pauseAll() {
        PRDownloader.pauseAll()
    }

    /**
     * Resume all downloads
     */
    fun resumeAll() {
        PRDownloader.resumeAll()
    }

    /**
     * Get download status
     */
    fun getStatus(taskId: String): Status? {
        return activeDownloads[taskId]?.let { downloadId ->
            PRDownloader.getStatus(downloadId)
        }
    }

    /**
     * Get all active download tasks
     */
    fun getActiveTasks(): List<DownloadTask> {
        return downloadTasks.values.toList()
    }

    /**
     * Clean up partial downloads
     */
    suspend fun cleanupPartialDownloads() {
        val modelsDir = File(context.getExternalFilesDir(null), "models")
        if (modelsDir.exists()) {
            modelsDir.walkTopDown().forEach { file ->
                if (file.isFile && file.name.endsWith(".downloading")) {
                    file.delete()
                }
            }
        }
    }

    /**
     * Get download directory for a model
     */
    private fun getModelDirectory(model: ModelInfo): File {
        val baseDir = File(context.getExternalFilesDir(null), "models")
        val categoryDir = model.category.value
        val frameworkDir = model.preferredFramework?.value ?: "default"
        return File(baseDir, "$categoryDir/$frameworkDir/${model.id}")
    }

    /**
     * Copy model to destination (useful for bundled models)
     */
    suspend fun copyBundledModel(assetPath: String, model: ModelInfo): String {
        return suspendCancellableCoroutine { cont ->
            try {
                val destinationDir = getModelDirectory(model)
                destinationDir.mkdirs()
                val destinationFile = File(destinationDir, "${model.id}.${model.format.value}")

                context.assets.open(assetPath).use { input ->
                    FileUtils.copyInputStreamToFile(input, destinationFile)
                }

                // Update model with local path
                model.localPath = destinationFile.absolutePath

                // Update repository
                kotlinx.coroutines.runBlocking {
                    repository.updateDownloadStatus(model.id, destinationFile.absolutePath)
                }

                cont.resume(destinationFile.absolutePath)
            } catch (e: Exception) {
                cont.resumeWithException(
                    DownloadException.StorageError("Failed to copy bundled model: ${e.message}")
                )
            }
        }
    }

    /**
     * Delete a downloaded model
     */
    suspend fun deleteModel(model: ModelInfo): Boolean {
        return try {
            model.localPath?.let { path ->
                val file = File(path)
                if (file.exists()) {
                    FileUtils.forceDelete(file.parentFile) // Delete model directory
                    repository.updateDownloadStatus(model.id, null)
                    true
                } else {
                    false
                }
            } ?: false
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get model storage size
     */
    fun getModelSize(model: ModelInfo): Long {
        return model.localPath?.let { path ->
            val file = File(path)
            if (file.exists()) {
                FileUtils.sizeOf(file)
            } else {
                0L
            }
        } ?: 0L
    }

    /**
     * Get total storage used by all models
     */
    fun getTotalStorageUsed(): Long {
        val modelsDir = File(context.getExternalFilesDir(null), "models")
        return if (modelsDir.exists()) {
            FileUtils.sizeOfDirectory(modelsDir)
        } else {
            0L
        }
    }

    private var lastBytes = 0L
    private var lastTime = System.currentTimeMillis()

    private fun calculateSpeed(currentBytes: Long, totalBytes: Long): Long {
        val currentTime = System.currentTimeMillis()
        val timeDiff = currentTime - lastTime
        val bytesDiff = currentBytes - lastBytes

        return if (timeDiff > 0) {
            val speed = (bytesDiff * 1000) / timeDiff
            lastBytes = currentBytes
            lastTime = currentTime
            speed
        } else {
            0L
        }
    }
}

/**
 * Download task information
 */
data class DownloadTask(
    val id: String,
    val modelId: String,
    val modelInfo: ModelInfo,
    val progress: Flow<DownloadProgress>
)

/**
 * Download progress with detailed information
 */
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val speedBytesPerSecond: Long = 0
) {
    val progressPercent: Int
        get() = if (totalBytes > 0) {
            ((bytesDownloaded.toDouble() / totalBytes) * 100).toInt()
        } else {
            0
        }

    val formattedSpeed: String
        get() = formatBytes(speedBytesPerSecond) + "/s"

    val formattedProgress: String
        get() = "${formatBytes(bytesDownloaded)} / ${formatBytes(totalBytes)}"

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            else -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
        }
    }
}

/**
 * Download states
 */
sealed class DownloadState {
    object STARTED : DownloadState()
    object DOWNLOADING : DownloadState()
    object PAUSED : DownloadState()
    object COMPLETED : DownloadState()
    object CANCELLED : DownloadState()
    data class FAILED(val error: DownloadException) : DownloadState()
}

/**
 * Download exceptions
 */
sealed class DownloadException(message: String) : Exception(message) {
    class InvalidURL(message: String) : DownloadException(message)
    class NetworkError(message: String) : DownloadException(message)
    class ServerError(message: String) : DownloadException(message)
    class StorageError(message: String) : DownloadException(message)
    class Unknown(message: String) : DownloadException(message)
}
