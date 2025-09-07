package com.runanywhere.sdk.services.download

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel

/**
 * Download progress tracking - matches iOS DownloadProgress
 */
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val estimatedTimeRemaining: Double? = null
) {
    val percentage: Double
        get() = if (totalBytes > 0) bytesDownloaded.toDouble() / totalBytes else 0.0
}

/**
 * Download state - matches iOS DownloadState
 */
sealed class DownloadState {
    object Pending : DownloadState()
    object Downloading : DownloadState()
    object Extracting : DownloadState()
    data class Retrying(val attempt: Int) : DownloadState()
    object Completed : DownloadState()
    data class Failed(val error: Throwable) : DownloadState()
    object Cancelled : DownloadState()
}

/**
 * Download task - matches iOS DownloadTask
 */
data class DownloadTask(
    val id: String,
    val modelId: String,
    val progress: Flow<DownloadProgress>,
    val job: Job
)

/**
 * Download strategy interface - matches iOS DownloadStrategy protocol
 */
interface DownloadStrategy {
    fun canHandle(model: ModelInfo): Boolean
    suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)? = null
    ): String
}

/**
 * Download service interface - matches iOS DownloadManager protocol
 */
interface DownloadService {
    /**
     * Download a model with progress tracking
     */
    suspend fun downloadModel(
        model: ModelInfo,
        progressHandler: ((DownloadProgress) -> Unit)? = null
    ): String

    /**
     * Stream download progress for a model
     */
    fun downloadModelStream(model: ModelInfo): Flow<DownloadProgress>

    /**
     * Cancel a download
     */
    fun cancelDownload(modelId: String)

    /**
     * Get active downloads
     */
    fun getActiveDownloads(): List<DownloadTask>

    /**
     * Check if a model is currently downloading
     */
    fun isDownloading(modelId: String): Boolean

    /**
     * Resume a download if resume data exists
     */
    suspend fun resumeDownload(modelId: String): String?
}

/**
 * Default download service implementation
 * Matches iOS AlamofireDownloadService pattern
 */
class DefaultDownloadService(
    private val fileManager: FileManager,
    private val networkService: NetworkService,
    private val strategies: List<DownloadStrategy> = emptyList()
) : DownloadService {

    private val logger = SDKLogger("DownloadService")
    private val activeTasks = mutableMapOf<String, DownloadTask>()
    private val downloadStates = mutableMapOf<String, MutableStateFlow<DownloadProgress>>()

    override suspend fun downloadModel(
        model: ModelInfo,
        progressHandler: ((DownloadProgress) -> Unit)?
    ): String {
        logger.info("Starting download for model: ${model.id}")

        // Check if already downloading
        if (isDownloading(model.id)) {
            throw SDKError.RuntimeError("Model ${model.id} is already downloading")
        }

        // Find appropriate strategy
        val strategy = strategies.firstOrNull { it.canHandle(model) }

        // Create destination folder
        val destinationFolder = fileManager.getModelDirectory(
            framework = model.preferredFramework?.name ?: "unknown",
            modelId = model.id
        )

        // Initialize progress tracking
        val progressFlow = MutableStateFlow(
            DownloadProgress(
                bytesDownloaded = 0,
                totalBytes = model.downloadSize ?: 0,
                state = DownloadState.Pending
            )
        )
        downloadStates[model.id] = progressFlow

        try {
            // Update state to downloading
            progressFlow.value = progressFlow.value.copy(state = DownloadState.Downloading)

            // Use strategy if available, otherwise use default download
            val localPath = if (strategy != null) {
                logger.debug("Using custom strategy for model: ${model.id}")
                strategy.download(model, destinationFolder) { percentage ->
                    val totalBytes = model.downloadSize ?: 0
                    val bytesDownloaded = (totalBytes * percentage).toLong()
                    progressFlow.value = DownloadProgress(
                        bytesDownloaded = bytesDownloaded,
                        totalBytes = totalBytes,
                        state = DownloadState.Downloading,
                        estimatedTimeRemaining = estimateTimeRemaining(bytesDownloaded, totalBytes)
                    )
                    progressHandler?.invoke(progressFlow.value)
                }
            } else {
                // Default download implementation
                downloadModelDefault(model, destinationFolder, progressFlow, progressHandler)
            }

            // Update state to completed
            progressFlow.value = progressFlow.value.copy(state = DownloadState.Completed)

            logger.info("Successfully downloaded model ${model.id} to: $localPath")
            return localPath

        } catch (e: CancellationException) {
            progressFlow.value = progressFlow.value.copy(state = DownloadState.Cancelled)
            throw SDKError.RuntimeError("Download cancelled for model ${model.id}")
        } catch (e: Exception) {
            progressFlow.value = progressFlow.value.copy(state = DownloadState.Failed(e))
            logger.error("Failed to download model ${model.id}", e)
            throw SDKError.ModelDownloadFailed("Failed to download model: ${e.message}")
        } finally {
            // Clean up
            downloadStates.remove(model.id)
            activeTasks.remove(model.id)
        }
    }

    override fun downloadModelStream(model: ModelInfo): Flow<DownloadProgress> = flow {
        val progressFlow = downloadStates[model.id] ?: MutableStateFlow(
            DownloadProgress(0, model.downloadSize ?: 0, DownloadState.Pending)
        )

        progressFlow.collect { progress ->
            emit(progress)
            if (progress.state is DownloadState.Completed ||
                progress.state is DownloadState.Failed ||
                progress.state is DownloadState.Cancelled) {
                // Terminal state reached
                return@collect
            }
        }
    }

    override fun cancelDownload(modelId: String) {
        logger.info("Cancelling download for model: $modelId")

        activeTasks[modelId]?.let { task ->
            task.job.cancel("User cancelled download")
            downloadStates[modelId]?.value = DownloadProgress(
                bytesDownloaded = downloadStates[modelId]?.value?.bytesDownloaded ?: 0,
                totalBytes = downloadStates[modelId]?.value?.totalBytes ?: 0,
                state = DownloadState.Cancelled
            )
        }

        activeTasks.remove(modelId)
    }

    override fun getActiveDownloads(): List<DownloadTask> {
        return activeTasks.values.toList()
    }

    override fun isDownloading(modelId: String): Boolean {
        return activeTasks.containsKey(modelId)
    }

    override suspend fun resumeDownload(modelId: String): String? {
        logger.info("Attempting to resume download for model: $modelId")

        // Check for resume data
        val resumeData = fileManager.getResumeData(modelId)
        if (resumeData != null) {
            logger.debug("Found resume data for model: $modelId")
            // TODO: Implement resume logic based on platform capabilities
            return null
        }

        logger.debug("No resume data found for model: $modelId")
        return null
    }

    /**
     * Default download implementation
     */
    private suspend fun downloadModelDefault(
        model: ModelInfo,
        destinationFolder: String,
        progressFlow: MutableStateFlow<DownloadProgress>,
        progressHandler: ((DownloadProgress) -> Unit)?
    ): String {
        val downloadUrl = model.downloadURL
            ?: throw SDKError.ConfigurationError("Model ${model.id} has no download URL")

        logger.debug("Downloading from URL: $downloadUrl")

        // Create destination file path
        val fileName = extractFileName(downloadUrl) ?: "${model.id}.bin"
        val destinationPath = "$destinationFolder/$fileName"

        // Ensure directory exists
        fileManager.createDirectory(destinationFolder)

        // Download with progress tracking
        networkService.downloadFile(
            url = downloadUrl,
            destinationPath = destinationPath,
            progressCallback = { bytesDownloaded, totalBytes ->
                val progress = DownloadProgress(
                    bytesDownloaded = bytesDownloaded,
                    totalBytes = totalBytes,
                    state = DownloadState.Downloading,
                    estimatedTimeRemaining = estimateTimeRemaining(bytesDownloaded, totalBytes)
                )
                progressFlow.value = progress
                progressHandler?.invoke(progress)
            }
        )

        // Verify download
        if (!fileManager.fileExists(destinationPath)) {
            throw SDKError.FileNotFound(destinationPath)
        }

        // TODO: Implement checksum verification
        // model.checksum?.let { expectedChecksum ->
        //     val actualChecksum = fileManager.calculateChecksum(destinationPath)
        //     if (actualChecksum != expectedChecksum) {
        //         fileManager.deleteFile(destinationPath)
        //         throw SDKError.ModelDownloadFailed("Checksum mismatch for model ${model.id}")
        //     }
        // }

        return destinationPath
    }

    /**
     * Estimate remaining download time
     */
    private fun estimateTimeRemaining(bytesDownloaded: Long, totalBytes: Long): Double? {
        if (bytesDownloaded == 0L || totalBytes == 0L) return null

        // Simple estimation - would need to track download rate for accurate estimate
        val percentComplete = bytesDownloaded.toDouble() / totalBytes
        if (percentComplete < 0.01) return null // Not enough data

        // This is a placeholder - real implementation would track download speed
        return null
    }

    /**
     * Extract filename from URL
     */
    private fun extractFileName(url: String): String? {
        return url.substringAfterLast('/').takeIf { it.isNotEmpty() }
    }
}

/**
 * File manager interface for model storage
 */
interface FileManager {
    fun getModelDirectory(framework: String, modelId: String): String
    fun createDirectory(path: String)
    fun fileExists(path: String): Boolean
    fun deleteFile(path: String): Boolean
    fun calculateChecksum(path: String): String
    fun getResumeData(modelId: String): ByteArray?
    fun saveResumeData(modelId: String, data: ByteArray)
    fun getModelStoragePath(): String
    fun getAvailableSpace(): Long
    fun getDirectorySize(path: String): Long
}

/**
 * Network service interface for downloads
 */
interface NetworkService {
    suspend fun downloadFile(
        url: String,
        destinationPath: String,
        progressCallback: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)? = null
    )
}
