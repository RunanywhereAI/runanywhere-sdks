package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.storage.FileSystem
import io.ktor.client.*
import io.ktor.client.plugins.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.utils.io.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Download progress information - EXACT copy of iOS DownloadProgress
 * Now includes multi-stage progress tracking matching iOS implementation.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Models/Output/DownloadProgress.swift
 */
data class DownloadProgress(
    /**
     * Current stage in the download pipeline
     * Matches iOS DownloadProgress.stage
     */
    val stage: DownloadStage = DownloadStage.DOWNLOADING,
    /**
     * Bytes downloaded (for download stage)
     */
    val bytesDownloaded: Long,
    /**
     * Total bytes to download
     */
    val totalBytes: Long,
    /**
     * Current download state (downloading, extracting, failed, etc.)
     */
    val state: DownloadState,
    /**
     * Estimated time remaining in seconds
     */
    val estimatedTimeRemaining: Double? = null,
    /**
     * Download speed in bytes per second
     */
    val speed: Double? = null,
    /**
     * Progress within current stage (0.0 to 1.0)
     * Matches iOS DownloadProgress.stageProgress
     */
    val stageProgress: Double = if (totalBytes > 0) bytesDownloaded.toDouble() / totalBytes else 0.0,
) {
    /**
     * Overall progress across all stages (0.0 to 1.0)
     * Matches iOS DownloadProgress.overallProgress computed property
     */
    val overallProgress: Double
        get() = stage.calculateOverallProgress(stageProgress)

    /**
     * Legacy percentage property (maps to stageProgress for download stage, overallProgress otherwise)
     * Matches iOS DownloadProgress.percentage computed property
     */
    val percentage: Double
        get() =
            when (stage) {
                DownloadStage.DOWNLOADING -> stageProgress
                else -> overallProgress
            }

    companion object {
        /**
         * Create progress for extraction stage
         * Matches iOS DownloadProgress.extraction(modelId:progress:totalBytes:)
         */
        @Suppress("UNUSED_PARAMETER")
        fun extraction(
            modelId: String,
            progress: Double,
            totalBytes: Long = 0,
        ): DownloadProgress =
            DownloadProgress(
                stage = DownloadStage.EXTRACTING,
                bytesDownloaded = (progress * totalBytes).toLong(),
                totalBytes = totalBytes,
                stageProgress = progress,
                state = DownloadState.Extracting,
            )

        /**
         * Create progress for validation stage
         */
        fun validating(
            progress: Double,
            totalBytes: Long = 0,
        ): DownloadProgress =
            DownloadProgress(
                stage = DownloadStage.VALIDATING,
                bytesDownloaded = totalBytes,
                totalBytes = totalBytes,
                stageProgress = progress,
                state = DownloadState.Downloading, // No specific validation state
            )

        /**
         * Create completed progress
         * Matches iOS DownloadProgress.completed(totalBytes:)
         */
        fun completed(totalBytes: Long): DownloadProgress =
            DownloadProgress(
                stage = DownloadStage.COMPLETED,
                bytesDownloaded = totalBytes,
                totalBytes = totalBytes,
                stageProgress = 1.0,
                state = DownloadState.Completed,
            )

        /**
         * Create failed progress
         * Matches iOS DownloadProgress.failed(_:bytesDownloaded:totalBytes:)
         */
        fun failed(
            error: Throwable,
            bytesDownloaded: Long = 0,
            totalBytes: Long = 0,
        ): DownloadProgress =
            DownloadProgress(
                stage = DownloadStage.DOWNLOADING,
                bytesDownloaded = bytesDownloaded,
                totalBytes = totalBytes,
                stageProgress = if (totalBytes > 0) bytesDownloaded.toDouble() / totalBytes else 0.0,
                state = DownloadState.Failed(error),
            )
    }
}

/**
 * Download state enumeration - EXACT copy of iOS DownloadState
 */
sealed class DownloadState {
    object Pending : DownloadState()

    object Downloading : DownloadState()

    object Extracting : DownloadState()

    data class Retrying(
        val attempt: Int,
    ) : DownloadState()

    object Completed : DownloadState()

    data class Failed(
        val error: Throwable,
    ) : DownloadState()

    object Cancelled : DownloadState()
}

/**
 * Download pipeline stages - EXACT copy of iOS DownloadStage
 * Used for calculating overall progress across multiple stages.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Models/Output/DownloadProgress.swift
 */
enum class DownloadStage {
    /** Downloading file - 0-80% of overall progress */
    DOWNLOADING,

    /** Extracting archive - 80-95% of overall progress */
    EXTRACTING,

    /** Validating downloaded content - 95-99% of overall progress */
    VALIDATING,

    /** Download complete - 100% */
    COMPLETED,

    ;

    /**
     * Display name for UI
     * Matches iOS DownloadStage.displayName
     */
    val displayName: String
        get() =
            when (this) {
                DOWNLOADING -> "Downloading"
                EXTRACTING -> "Extracting"
                VALIDATING -> "Validating"
                COMPLETED -> "Completed"
            }

    /**
     * Weight of this stage for overall progress calculation
     * Download: 0-80%, Extraction: 80-95%, Validation: 95-99%
     * Matches iOS DownloadStage.progressRange
     */
    val progressRange: Pair<Double, Double>
        get() =
            when (this) {
                DOWNLOADING -> 0.0 to 0.80
                EXTRACTING -> 0.80 to 0.95
                VALIDATING -> 0.95 to 0.99
                COMPLETED -> 1.0 to 1.0
            }

    /**
     * Weight for this stage in overall progress calculation.
     * Derived from progressRange for convenience.
     */
    val weight: Double
        get() = progressRange.second - progressRange.first

    /**
     * Starting progress for this stage.
     * Matches iOS stageStartProgress computed property.
     */
    val startProgress: Double
        get() = progressRange.first

    /**
     * Calculate overall progress given stage-specific progress (0.0 to 1.0)
     * Matches iOS calculateOverallProgress method.
     */
    fun calculateOverallProgress(stageProgress: Double): Double =
        when (this) {
            COMPLETED -> 1.0
            else -> startProgress + (stageProgress * weight)
        }
}

/**
 * Download task information - EXACT copy of iOS DownloadTask
 * Using Flow instead of AsyncStream, Deferred instead of Swift Task
 */
data class DownloadTask(
    val id: String,
    val modelId: String,
    val progress: Flow<DownloadProgress>,
    val result: Deferred<String>, // URL as String in Kotlin
)

/**
 * Download errors - EXACT copy of iOS DownloadError
 */
sealed class DownloadError : Exception() {
    object InvalidURL : DownloadError()

    data class NetworkError(
        override val cause: Throwable?,
    ) : DownloadError()

    object Timeout : DownloadError()

    object PartialDownload : DownloadError()

    object ChecksumMismatch : DownloadError()

    data class ExtractionFailed(
        val reason: String,
    ) : DownloadError()

    data class UnsupportedArchive(
        val format: String,
    ) : DownloadError()

    object Unknown : DownloadError()

    object InvalidResponse : DownloadError()

    data class HttpError(
        val code: Int,
    ) : DownloadError()

    object Cancelled : DownloadError()

    object InsufficientSpace : DownloadError()

    object ModelNotFound : DownloadError()

    object ConnectionLost : DownloadError()

    override val message: String
        get() =
            when (this) {
                is InvalidURL -> "Invalid download URL"
                is NetworkError -> "Network error: ${cause?.message}"
                is Timeout -> "Download timeout"
                is PartialDownload -> "Partial download - file incomplete"
                is ChecksumMismatch -> "Downloaded file checksum doesn't match expected"
                is ExtractionFailed -> "Archive extraction failed: $reason"
                is UnsupportedArchive -> "Unsupported archive format: $format"
                is Unknown -> "Unknown download error"
                is InvalidResponse -> "Invalid server response"
                is HttpError -> "HTTP error: $code"
                is Cancelled -> "Download was cancelled"
                is InsufficientSpace -> "Insufficient storage space"
                is ModelNotFound -> "Model not found"
                is ConnectionLost -> "Network connection lost"
            }
}

/**
 * Download policy for models - EXACT copy of iOS DownloadPolicy
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Models/Configuration/DownloadConfiguration.swift
 */
enum class DownloadPolicy(
    val value: String,
) {
    /**
     * Download automatically if needed
     */
    AUTOMATIC("automatic"),

    /**
     * Only download on WiFi
     */
    WIFI_ONLY("wifi_only"),

    /**
     * Require user confirmation
     */
    MANUAL("manual"),

    /**
     * Don't download, fail if not available
     */
    NEVER("never"),
}

/**
 * Configuration for download behavior - EXACT copy of iOS DownloadConfiguration
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Models/Configuration/DownloadConfiguration.swift
 */
data class DownloadConfiguration(
    /**
     * Download policy
     */
    val policy: DownloadPolicy = DownloadPolicy.AUTOMATIC,
    val maxConcurrentDownloads: Int = 3,
    val retryCount: Int = 3,
    val retryDelay: Double = 2.0, // TimeInterval equivalent
    val timeout: Double = 300.0, // TimeInterval equivalent
    val chunkSize: Int = 1024 * 1024, // 1MB chunks
    val resumeOnFailure: Boolean = true,
    val verifyChecksum: Boolean = true,
    /**
     * Enable background downloads
     */
    val enableBackgroundDownloads: Boolean = false,
) {
    /**
     * Check if download should be allowed based on policy
     * Matches iOS DownloadConfiguration.shouldAllowDownload(isWiFi:userConfirmed:)
     *
     * @param isWiFi Whether device is on WiFi
     * @param userConfirmed Whether user has confirmed download
     * @return true if download should be allowed
     */
    fun shouldAllowDownload(isWiFi: Boolean = false, userConfirmed: Boolean = false): Boolean {
        return when (policy) {
            DownloadPolicy.AUTOMATIC -> true
            DownloadPolicy.WIFI_ONLY -> isWiFi
            DownloadPolicy.MANUAL -> userConfirmed
            DownloadPolicy.NEVER -> false
        }
    }
}

/**
 * Protocol for custom download strategies - EXACT copy of iOS DownloadStrategy
 */
interface DownloadStrategy {
    fun canHandle(model: ModelInfo): Boolean

    suspend fun download(
        model: ModelInfo,
        to: String, // URL -> String in Kotlin
        progressHandler: ((Double) -> Unit)? = null,
    ): String
}

/**
 * Protocol for download management operations - EXACT copy of iOS DownloadManager
 */
interface DownloadManager {
    suspend fun downloadModel(model: ModelInfo): DownloadTask

    fun cancelDownload(taskId: String)

    fun activeDownloads(): List<DownloadTask>
}

/**
 * Platform-specific download implementation
 * Each platform provides its own optimized downloader
 */
internal expect suspend fun downloadWithPlatformImplementation(
    downloadURL: String,
    destinationPath: String,
    modelId: String,
    expectedSize: Long,
    progressChannel: Channel<DownloadProgress>,
)

/**
 * KtorDownloadService - EXACT 1:1 copy of iOS AlamofireDownloadService
 * Using Ktor instead of Alamofire, but identical business logic, method names, and architecture
 */
@OptIn(ExperimentalUuidApi::class)
class KtorDownloadService(
    internal val configuration: DownloadConfiguration = DownloadConfiguration(),
    internal val fileSystem: FileSystem,
) : DownloadManager {
    // MARK: - Properties (EXACT copy of iOS)

    internal val httpClient: HttpClient
    private val activeDownloadRequests: MutableMap<String, Job> = mutableMapOf()
    private val activeDownloadTasks: MutableMap<String, DownloadTask> = mutableMapOf()
    private val downloadSemaphore = kotlinx.coroutines.sync.Semaphore(configuration.maxConcurrentDownloads)
    private val logger = SDKLogger("KtorDownloadService")
    internal val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // MARK: - Custom Download Strategies (EXACT copy of iOS)

    // / Storage for custom download strategies provided by host app
    private val customStrategies: MutableList<DownloadStrategy> = mutableListOf()

    // MARK: - Initialization (EXACT copy of iOS)

    init {
        // SIMPLIFIED HTTP CLIENT - NO buffering, NO retries, NO plugins
        // This prevents Ktor from buffering the entire response in memory
        httpClient =
            HttpClient {
                // ONLY timeout - nothing else that could buffer
                install(HttpTimeout) {
                    requestTimeoutMillis = (configuration.timeout * 1000).toLong()
                    connectTimeoutMillis = (configuration.timeout * 1000).toLong()
                    socketTimeoutMillis = (configuration.timeout * 2 * 1000).toLong()
                }

                // Disable ALL automatic response handling to prevent buffering
                expectSuccess = false
            }
    }

    // MARK: - DownloadManager Protocol (EXACT copy of iOS)

    override suspend fun downloadModel(model: ModelInfo): DownloadTask {
        // Find a download strategy that can handle this model
        // This checks both host app custom strategies and module-provided strategies
        val strategy = findStrategy(model)
        if (strategy != null) {
            logger.info("Using custom strategy for model: ${model.id}")
            return downloadModelWithCustomStrategy(model, strategy)
        }

        // No custom strategy found, use default download
        val downloadURL =
            model.downloadURL
                ?: throw DownloadError.InvalidURL

        val taskId = Uuid.random().toString()
        val progressChannel = Channel<DownloadProgress>(Channel.UNLIMITED)

        // Create download task with semaphore for concurrency control
        val result =
            serviceScope.async {
                downloadSemaphore.acquire() // Limit concurrent downloads
                try {
                    // Use framework-specific folder if available (matching iOS logic)
                    val modelFolder =
                        if (model.preferredFramework != null || model.compatibleFrameworks.isNotEmpty()) {
                            val framework = model.preferredFramework ?: model.compatibleFrameworks.first()
                            getModelFolder(model.id, framework)
                        } else {
                            getModelFolder(model.id)
                        }

                    val destinationPath = "$modelFolder/${model.id}.${model.format.name.lowercase()}"

                    // Log download start (matching iOS)
                    logger.info(
                        "Starting download - modelId: ${model.id}, url: $downloadURL, expectedSize: ${model.downloadSize ?: 0}, destination: $destinationPath",
                    )

                    // Ensure directory exists
                    fileSystem.createDirectory(modelFolder)

                    // Use platform-specific download implementation
                    downloadWithPlatformImplementation(
                        downloadURL = downloadURL,
                        destinationPath = destinationPath,
                        modelId = model.id,
                        expectedSize = model.downloadSize ?: 0L,
                        progressChannel = progressChannel,
                    )

                    // Update model with local path in BOTH registry AND repository
                    val updatedModel =
                        model.copy(
                            localPath = destinationPath,
                            updatedAt =
                                com.runanywhere.sdk.utils.SimpleInstant
                                    .now(),
                        )

                    // 1. Update in-memory registry
                    ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

                    // 2. Save to persistent repository (database)
                    try {
                        ServiceContainer.shared.modelInfoService.saveModel(updatedModel)
                        logger.info(
                            "Model saved to repository - modelId: ${model.id}, localPath: $destinationPath, isDownloaded: ${updatedModel.isDownloaded}",
                        )
                    } catch (e: Exception) {
                        logger.error("Failed to save model to repository: ${e.message}", e)
                    }

                    logger.info(
                        "Model updated in registry - modelId: ${model.id}, localPath: $destinationPath, isDownloaded: ${updatedModel.isDownloaded}",
                    )

                    destinationPath
                } catch (e: kotlinx.coroutines.CancellationException) {
                    progressChannel.trySend(
                        DownloadProgress(
                            bytesDownloaded = 0,
                            totalBytes = model.downloadSize ?: 0,
                            state = DownloadState.Failed(DownloadError.Cancelled),
                        ),
                    )
                    throw DownloadError.Cancelled
                } catch (e: Exception) {
                    val downloadError = mapKtorError(e)
                    progressChannel.trySend(
                        DownloadProgress(
                            bytesDownloaded = 0,
                            totalBytes = model.downloadSize ?: 0,
                            state = DownloadState.Failed(downloadError),
                        ),
                    )

                    logger.error(
                        "Download failed - modelId: ${model.id}, url: $downloadURL, error: ${e.message}, errorType: ${e::class.simpleName}",
                        e,
                    )
                    throw downloadError
                } finally {
                    progressChannel.close()
                    downloadSemaphore.release() // Release semaphore for other downloads
                }
            }

        val progressFlow =
            flow {
                for (progress in progressChannel) {
                    emit(progress)
                }
            }

        val task =
            DownloadTask(
                id = taskId,
                modelId = model.id,
                progress = progressFlow,
                result = result,
            )

        // Store the task for tracking
        activeDownloadTasks[taskId] = task

        // Clean up when task completes
        result.invokeOnCompletion {
            activeDownloadTasks.remove(taskId)
        }

        return task
    }

    override fun cancelDownload(taskId: String) {
        activeDownloadTasks[taskId]?.let { task ->
            task.result.cancel()
            activeDownloadTasks.remove(taskId)
            logger.info("Cancelled download task: $taskId")
        }
    }

    override fun activeDownloads(): List<DownloadTask> = activeDownloadTasks.values.toList()

    // MARK: - Custom Strategy Support (EXACT copy of iOS)

    // / Register a custom download strategy from host app
    fun registerStrategy(strategy: DownloadStrategy) {
        customStrategies.add(0, strategy) // Custom strategies have priority
        logger.info("Registered custom download strategy")
    }

    /**
     * Find a download strategy that can handle the given model.
     * Uses ModuleRegistryMetadata to get strategies from registered modules.
     * Matches iOS findCustomStrategy(for:) implementation.
     *
     * @param model The model to find a strategy for
     * @return A download strategy that can handle the model, or null
     */
    private fun findStrategy(model: ModelInfo): DownloadStrategy? {
        // First check manually registered custom strategies (host app priority)
        for (strategy in customStrategies) {
            if (strategy.canHandle(model)) {
                return strategy
            }
        }

        // Then check ModuleRegistryMetadata for module-provided strategies
        // First try the model's preferred framework
        model.preferredFramework?.let { framework ->
            val strategy = com.runanywhere.sdk.core.ModuleRegistryMetadata.downloadStrategy(framework)
            if (strategy != null && strategy.canHandle(model)) {
                return strategy
            }
        }

        // Try all registered download strategies
        for (strategy in com.runanywhere.sdk.core.ModuleRegistryMetadata.allDownloadStrategies) {
            if (strategy.canHandle(model)) {
                return strategy
            }
        }

        return null
    }

    // / Helper to download using a custom strategy (EXACT copy of iOS)
    private suspend fun downloadModelWithCustomStrategy(
        model: ModelInfo,
        strategy: DownloadStrategy,
    ): DownloadTask {
        logger.info("Using custom strategy for model: ${model.id}")

        val taskId = Uuid.random().toString()
        val progressChannel = Channel<DownloadProgress>(Channel.UNLIMITED)

        // Create download task with semaphore for concurrency control
        val result =
            serviceScope.async {
                downloadSemaphore.acquire() // Limit concurrent downloads
                try {
                    val destinationFolder = getDestinationFolder(model.id, model.preferredFramework)

                    val resultPath =
                        strategy.download(
                            model = model,
                            to = destinationFolder,
                            progressHandler = { progress ->
                                progressChannel.trySend(
                                    DownloadProgress(
                                        bytesDownloaded = (progress * (model.downloadSize ?: 100)).toLong(),
                                        totalBytes = model.downloadSize ?: 100,
                                        state = DownloadState.Downloading,
                                    ),
                                )
                            },
                        )

                    // Update progress to completed
                    progressChannel.trySend(
                        DownloadProgress(
                            bytesDownloaded = model.downloadSize ?: 100,
                            totalBytes = model.downloadSize ?: 100,
                            state = DownloadState.Completed,
                        ),
                    )

                    logger.info(
                        "Custom strategy download completed - modelId: ${model.id}, localPath: $resultPath",
                    )

                    // Update model with local path in BOTH registry AND repository
                    val updatedModel =
                        model.copy(
                            localPath = resultPath,
                            updatedAt =
                                com.runanywhere.sdk.utils.SimpleInstant
                                    .now(),
                        )

                    // 1. Update in-memory registry
                    ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

                    // 2. Save to persistent repository (database)
                    try {
                        ServiceContainer.shared.modelInfoService.saveModel(updatedModel)
                        logger.info(
                            "Model saved to repository - modelId: ${model.id}, localPath: $resultPath, isDownloaded: ${updatedModel.isDownloaded}",
                        )
                    } catch (e: Exception) {
                        logger.error("Failed to save model to repository: ${e.message}", e)
                    }

                    logger.info(
                        "Model updated in registry - modelId: ${model.id}, localPath: $resultPath, isDownloaded: ${updatedModel.isDownloaded}",
                    )

                    resultPath
                } catch (e: Exception) {
                    progressChannel.trySend(
                        DownloadProgress(
                            bytesDownloaded = 0,
                            totalBytes = model.downloadSize ?: 0,
                            state = DownloadState.Failed(e),
                        ),
                    )
                    throw e
                } finally {
                    progressChannel.close()
                    downloadSemaphore.release() // Release semaphore for other downloads
                }
            }

        val progressFlow =
            flow {
                for (progress in progressChannel) {
                    emit(progress)
                }
            }

        val task =
            DownloadTask(
                id = taskId,
                modelId = model.id,
                progress = progressFlow,
                result = result,
            )

        // Store the task for tracking
        activeDownloadTasks[taskId] = task

        // Clean up when task completes
        result.invokeOnCompletion {
            activeDownloadTasks.remove(taskId)
        }

        return task
    }

    // / Helper to get destination folder for a model (EXACT copy of iOS)
    private fun getDestinationFolder(
        modelId: String,
        framework: InferenceFramework? = null,
    ): String =
        if (framework != null) {
            getModelFolder(modelId, framework)
        } else {
            getModelFolder(modelId)
        }

    // Model folder helpers - Use centralized ModelPathUtils
    private fun getModelFolder(
        modelId: String,
        framework: InferenceFramework,
    ): String = ModelPathUtils.getModelFolder(modelId, framework)

    private fun getModelFolder(modelId: String): String = ModelPathUtils.getModelFolder(modelId)

    // MARK: - Helper Methods

    private fun mapKtorError(error: Throwable): DownloadError =
        when (error) {
            is HttpRequestTimeoutException -> DownloadError.Timeout
            is kotlinx.io.IOException -> DownloadError.NetworkError(error)
            is kotlinx.coroutines.CancellationException -> DownloadError.Cancelled
            else -> DownloadError.Unknown
        }

    private fun mapHttpError(statusCode: Int): DownloadError =
        when (statusCode) {
            in 400..499 -> DownloadError.HttpError(statusCode)
            in 500..599 -> DownloadError.HttpError(statusCode)
            else -> DownloadError.InvalidResponse
        }

    // MARK: - Public Methods (EXACT copy of iOS)

    // / Pause all active downloads
    fun pauseAll() {
        // Note: Ktor doesn't have direct pause/resume like Alamofire
        // This would need platform-specific implementation
        logger.info("Paused all downloads")
    }

    // / Resume all paused downloads
    fun resumeAll() {
        // Note: Ktor doesn't have direct pause/resume like Alamofire
        // This would need platform-specific implementation
        logger.info("Resumed all downloads")
    }

    // / Check if service is healthy
    @Suppress("FunctionOnlyReturningConstant") // TODO: Implement proper health check
    fun isHealthy(): Boolean = true

    fun cleanup() {
        activeDownloadRequests.values.forEach { it.cancel() }
        activeDownloadRequests.clear()
        httpClient.close()
    }
}

// MARK: - Extensions for Resumable Downloads (EXACT copy of iOS)

/**
 * Extension for resume functionality - EXACT copy of iOS extension
 */
@OptIn(ExperimentalUuidApi::class)
suspend fun KtorDownloadService.downloadModelWithResume(
    model: ModelInfo,
    resumeData: ByteArray? = null,
): DownloadTask {
    val downloadURL =
        model.downloadURL
            ?: throw DownloadError.InvalidURL

    val taskId = Uuid.random().toString()
    val progressChannel = Channel<DownloadProgress>(Channel.UNLIMITED)

    // Create download task using service scope
    val result =
        serviceScope.async {
            try {
                // Use framework-specific folder if available (matching iOS logic)
                val modelFolder =
                    if (model.preferredFramework != null || model.compatibleFrameworks.isNotEmpty()) {
                        val framework = model.preferredFramework ?: model.compatibleFrameworks.first()
                        getModelFolder(model.id, framework)
                    } else {
                        getModelFolder(model.id)
                    }

                val destinationPath = "$modelFolder/${model.id}.${model.format.name.lowercase()}"

                // Check for partial file and resume data
                var startByte = 0L
                if (resumeData != null && fileSystem.exists(destinationPath)) {
                    startByte = fileSystem.fileSize(destinationPath)
                }

                // Create HTTP request with Range header for resume
                val response =
                    httpClient
                        .prepareGet(downloadURL) {
                            if (startByte > 0) {
                                header(HttpHeaders.Range, "bytes=$startByte-")
                            }
                        }.execute()

                if (!response.status.isSuccess() && response.status.value != 206) {
                    // Save resume data if available
                    saveResumeData(ByteArray(0), model.id) // Placeholder for resume data
                    throw mapHttpError(response.status.value)
                }

                val contentLength = response.contentLength() ?: model.downloadSize ?: 0L
                val totalLength = contentLength + startByte
                val channel = response.bodyAsChannel()

                // Use temp file for new data
                val tempPath = "$destinationPath.tmp"

                var bytesDownloaded = startByte
                val buffer = ByteArray(configuration.chunkSize)

                // If resuming, copy existing file to temp
                if (startByte > 0 && fileSystem.exists(destinationPath)) {
                    fileSystem.copy(destinationPath, tempPath)
                } else {
                    fileSystem.writeBytes(tempPath, ByteArray(0))
                }

                while (!channel.isClosedForRead) {
                    val bytesRead = channel.readAvailable(buffer, 0, buffer.size)
                    if (bytesRead <= 0) break

                    // Append chunk directly to temp file
                    val chunkData = ByteArray(bytesRead)
                    buffer.copyInto(chunkData, 0, 0, bytesRead)
                    fileSystem.appendBytes(tempPath, chunkData)
                    bytesDownloaded += bytesRead

                    // Report progress
                    val progress =
                        DownloadProgress(
                            bytesDownloaded = bytesDownloaded,
                            totalBytes = totalLength,
                            state = DownloadState.Downloading,
                        )
                    progressChannel.trySend(progress)
                }

                // Move temp file to final destination
                fileSystem.move(tempPath, destinationPath)

                // Final progress update
                progressChannel.trySend(
                    DownloadProgress(
                        bytesDownloaded = totalLength,
                        totalBytes = totalLength,
                        state = DownloadState.Completed,
                    ),
                )

                destinationPath
            } catch (e: Exception) {
                // Save resume data if download failed
                saveResumeData(ByteArray(0), model.id) // Placeholder for resume data

                val downloadError = mapKtorError(e)
                progressChannel.trySend(
                    DownloadProgress(
                        bytesDownloaded = 0,
                        totalBytes = model.downloadSize ?: 0,
                        state = DownloadState.Failed(downloadError),
                    ),
                )
                throw downloadError
            } finally {
                progressChannel.close()
            }
        }

    val progressFlow =
        flow {
            for (progress in progressChannel) {
                emit(progress)
            }
        }

    return DownloadTask(
        id = taskId,
        modelId = model.id,
        progress = progressFlow,
        result = result,
    )
}

// Extension functions using centralized ModelPathUtils
private fun KtorDownloadService.getModelFolder(
    modelId: String,
    framework: InferenceFramework,
): String = ModelPathUtils.getModelFolder(modelId, framework)

private fun KtorDownloadService.getModelFolder(modelId: String): String = ModelPathUtils.getModelFolder(modelId)

private fun mapKtorError(error: Throwable): DownloadError =
    when (error) {
        is HttpRequestTimeoutException -> DownloadError.Timeout
        is kotlinx.io.IOException -> DownloadError.NetworkError(error)
        is kotlinx.coroutines.CancellationException -> DownloadError.Cancelled
        else -> DownloadError.Unknown
    }

private fun mapHttpError(statusCode: Int): DownloadError =
    when (statusCode) {
        in 400..499 -> DownloadError.HttpError(statusCode)
        in 500..599 -> DownloadError.HttpError(statusCode)
        else -> DownloadError.InvalidResponse
    }

private suspend fun saveResumeData(
    data: ByteArray,
    modelId: String,
) {
    try {
        val fileSystem = ServiceContainer.shared.fileSystem
        val resumePath = "${fileSystem.getTempDirectory()}/resume_$modelId"
        fileSystem.writeBytes(resumePath, data)
    } catch (e: Exception) {
        val logger = SDKLogger("KtorDownloadService")
        logger.error("Failed to save resume data for $modelId", e)
    }
}

suspend fun getResumeData(modelId: String): ByteArray? =
    try {
        val fileSystem = ServiceContainer.shared.fileSystem
        val resumePath = "${fileSystem.getTempDirectory()}/resume_$modelId"
        if (fileSystem.exists(resumePath)) {
            fileSystem.readBytes(resumePath)
        } else {
            null
        }
    } catch (e: Exception) {
        val logger = SDKLogger("KtorDownloadService")
        logger.error("Failed to load resume data for $modelId", e)
        null
    }

// MARK: - Interface compatibility with existing DownloadService

/**
 * Existing DownloadService interface - kept for backward compatibility
 */
interface DownloadService {
    suspend fun downloadModel(
        model: ModelInfo,
        progressHandler: ((DownloadProgress) -> Unit)? = null,
    ): String

    fun downloadModelStream(model: ModelInfo): Flow<DownloadProgress>

    fun cancelDownload(modelId: String)

    fun getActiveDownloads(): List<DownloadTask>

    fun isDownloading(modelId: String): Boolean

    suspend fun resumeDownload(modelId: String): String?
}

/**
 * Adapter to make KtorDownloadService work with existing DownloadService interface
 */
class KtorDownloadServiceAdapter(
    private val ktorService: KtorDownloadService,
) : DownloadService {
    private val activeTasks = mutableMapOf<String, DownloadTask>()
    private val adapterScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override suspend fun downloadModel(
        model: ModelInfo,
        progressHandler: ((DownloadProgress) -> Unit)?,
    ): String {
        val task = ktorService.downloadModel(model)
        activeTasks[model.id] = task

        // Start progress monitoring if handler provided
        progressHandler?.let { handler ->
            adapterScope.launch {
                task.progress.collect { progress ->
                    handler(progress)
                }
            }
        }

        try {
            return task.result.await()
        } finally {
            activeTasks.remove(model.id)
        }
    }

    override fun downloadModelStream(model: ModelInfo): Flow<DownloadProgress> =
        flow {
            val task = ktorService.downloadModel(model)
            activeTasks[model.id] = task

            task.progress.collect { progress ->
                emit(progress)
                // Clean up when download is complete or failed
                if (progress.state is DownloadState.Completed ||
                    progress.state is DownloadState.Failed ||
                    progress.state is DownloadState.Cancelled
                ) {
                    activeTasks.remove(model.id)
                }
            }
        }

    override fun cancelDownload(modelId: String) {
        activeTasks[modelId]?.let { task ->
            ktorService.cancelDownload(task.id)
            activeTasks.remove(modelId)
        }
    }

    override fun getActiveDownloads(): List<DownloadTask> = activeTasks.values.toList()

    override fun isDownloading(modelId: String): Boolean = activeTasks.containsKey(modelId)

    override suspend fun resumeDownload(modelId: String): String? {
        // Not implemented yet - would need to store resume data
        return null
    }
}
