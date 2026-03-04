/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Download extension for CppBridge.
 * Provides download manager bridge for C++ core model download operations.
 *
 * Follows iOS CppBridge+Download.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Download bridge that provides download manager callbacks for C++ core model download operations.
 *
 * The C++ core needs download manager functionality for:
 * - Downloading model files from remote URLs
 * - Tracking download progress and status
 * - Managing concurrent downloads
 * - Resuming interrupted downloads
 * - Validating downloaded files (checksum verification)
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgeModelPaths] and [CppBridgeModelRegistry] are registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 * - Downloads are executed on a background thread pool
 */
object CppBridgeDownload {
    /**
     * Download status constants matching C++ RAC_DOWNLOAD_STATUS_* values.
     */
    object DownloadStatus {
        /** Download is queued but not started */
        const val QUEUED = 0

        /** Download is in progress */
        const val DOWNLOADING = 1

        /** Download is paused */
        const val PAUSED = 2

        /** Download completed successfully */
        const val COMPLETED = 3

        /** Download failed */
        const val FAILED = 4

        /** Download was cancelled */
        const val CANCELLED = 5

        /** Download is verifying checksum */
        const val VERIFYING = 6

        /**
         * Get a human-readable name for the download status.
         */
        fun getName(status: Int): String =
            when (status) {
                QUEUED -> "QUEUED"
                DOWNLOADING -> "DOWNLOADING"
                PAUSED -> "PAUSED"
                COMPLETED -> "COMPLETED"
                FAILED -> "FAILED"
                CANCELLED -> "CANCELLED"
                VERIFYING -> "VERIFYING"
                else -> "UNKNOWN($status)"
            }

        /**
         * Check if the download status indicates completion (success or failure).
         */
        fun isTerminal(status: Int): Boolean = status in listOf(COMPLETED, FAILED, CANCELLED)
    }

    /**
     * Download error codes matching C++ RAC_DOWNLOAD_ERROR_* values.
     */
    object DownloadError {
        /** No error */
        const val NONE = 0

        /** Network error (connection failed, etc.) */
        const val NETWORK_ERROR = 1

        /** File write error */
        const val FILE_ERROR = 2

        /** Not enough storage space */
        const val INSUFFICIENT_STORAGE = 3

        /** Invalid URL */
        const val INVALID_URL = 4

        /** Checksum verification failed */
        const val CHECKSUM_FAILED = 5

        /** Download was cancelled */
        const val CANCELLED = 6

        /** Server error (4xx or 5xx response) */
        const val SERVER_ERROR = 7

        /** Download timeout */
        const val TIMEOUT = 8

        /** Network is unavailable (no internet connection) */
        const val NETWORK_UNAVAILABLE = 9

        /** DNS resolution failed */
        const val DNS_ERROR = 10

        /** SSL/TLS error */
        const val SSL_ERROR = 11

        /** Unknown error */
        const val UNKNOWN = 99

        /**
         * Get a human-readable name for the error code.
         */
        fun getName(error: Int): String =
            when (error) {
                NONE -> "NONE"
                NETWORK_ERROR -> "NETWORK_ERROR"
                FILE_ERROR -> "FILE_ERROR"
                INSUFFICIENT_STORAGE -> "INSUFFICIENT_STORAGE"
                INVALID_URL -> "INVALID_URL"
                CHECKSUM_FAILED -> "CHECKSUM_FAILED"
                CANCELLED -> "CANCELLED"
                SERVER_ERROR -> "SERVER_ERROR"
                TIMEOUT -> "TIMEOUT"
                NETWORK_UNAVAILABLE -> "NETWORK_UNAVAILABLE"
                DNS_ERROR -> "DNS_ERROR"
                SSL_ERROR -> "SSL_ERROR"
                UNKNOWN -> "UNKNOWN"
                else -> "UNKNOWN($error)"
            }

        /**
         * Get a user-friendly error message for the error code.
         */
        fun getUserMessage(error: Int): String =
            when (error) {
                NONE -> "No error"
                NETWORK_ERROR -> "Network error. Please check your internet connection and try again."
                FILE_ERROR -> "Failed to save the file. Please check available storage."
                INSUFFICIENT_STORAGE -> "Not enough storage space. Please free up some space and try again."
                INVALID_URL -> "Invalid download URL."
                CHECKSUM_FAILED -> "File verification failed. The download may be corrupted."
                CANCELLED -> "Download was cancelled."
                SERVER_ERROR -> "Server error. Please try again later."
                TIMEOUT -> "Connection timed out. Please check your internet connection and try again."
                NETWORK_UNAVAILABLE -> "No internet connection. Please check your network settings and try again."
                DNS_ERROR -> "Unable to connect to server. Please check your internet connection."
                SSL_ERROR -> "Secure connection failed. Please try again."
                UNKNOWN -> "An unexpected error occurred. Please try again."
                else -> "Download failed. Please try again."
            }
    }

    /**
     * Download priority levels.
     */
    object DownloadPriority {
        /** Low priority (background downloads) */
        const val LOW = 0

        /** Normal priority (default) */
        const val NORMAL = 1

        /** High priority (user-requested) */
        const val HIGH = 2

        /** Urgent priority (immediate start) */
        const val URGENT = 3
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeDownload"

    /**
     * Default buffer size for file downloads (8 KB).
     */
    private const val DEFAULT_BUFFER_SIZE = 8192

    /**
     * Default connection timeout in milliseconds.
     */
    private const val DEFAULT_CONNECT_TIMEOUT_MS = 30_000

    /**
     * Default read timeout in milliseconds.
     */
    private const val DEFAULT_READ_TIMEOUT_MS = 60_000

    /**
     * Maximum concurrent downloads.
     */
    private const val MAX_CONCURRENT_DOWNLOADS = 3

    /**
     * Background executor for download operations.
     */
    private val downloadExecutor =
        Executors.newFixedThreadPool(MAX_CONCURRENT_DOWNLOADS) { runnable ->
            Thread(runnable, "runanywhere-download").apply {
                isDaemon = true
            }
        }

    /**
     * Active downloads map.
     * Key: Download ID
     * Value: [DownloadTask] instance
     */
    private val activeDownloads = ConcurrentHashMap<String, DownloadTask>()

    /**
     * Download futures for cancellation.
     */
    private val downloadFutures = ConcurrentHashMap<String, Future<*>>()

    // Lock for cancel/pause/resume operations to make check-then-act sequences atomic
    private val downloadLock = Any()

    /**
     * Optional listener for download events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var downloadListener: DownloadListener? = null

    /**
     * Optional provider for custom download behavior.
     * Set this to customize download logic (e.g., use OkHttp instead of HttpURLConnection).
     */
    @Volatile
    var downloadProvider: DownloadProvider? = null

    /**
     * Download task data class tracking a single download.
     *
     * @param downloadId Unique identifier for this download
     * @param url The URL to download from
     * @param destinationPath The local file path to save to
     * @param modelId The model ID (for associating with model registry)
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @param status Current download status
     * @param error Error code if status is FAILED
     * @param totalBytes Total file size in bytes (-1 if unknown)
     * @param downloadedBytes Bytes downloaded so far
     * @param startedAt Timestamp when download started
     * @param completedAt Timestamp when download completed (or failed)
     * @param priority Download priority
     * @param expectedChecksum Expected checksum for verification (null to skip verification)
     */
    data class DownloadTask(
        val downloadId: String,
        val url: String,
        val destinationPath: String,
        val modelId: String,
        val modelType: Int,
        @Volatile var status: Int = DownloadStatus.QUEUED,
        @Volatile var error: Int = DownloadError.NONE,
        @Volatile var totalBytes: Long = -1L,
        @Volatile var downloadedBytes: Long = 0L,
        val startedAt: Long = System.currentTimeMillis(),
        @Volatile var completedAt: Long = 0L,
        val priority: Int = DownloadPriority.NORMAL,
        val expectedChecksum: String? = null,
    ) {
        /**
         * Get the download progress as a percentage (0-100).
         */
        fun getProgress(): Int {
            if (totalBytes <= 0) return 0
            return ((downloadedBytes * 100) / totalBytes).toInt().coerceIn(0, 100)
        }

        /**
         * Get the status name.
         */
        fun getStatusName(): String = DownloadStatus.getName(status)

        /**
         * Get the error name.
         */
        fun getErrorName(): String = DownloadError.getName(error)

        /**
         * Check if the download is still in progress.
         */
        fun isActive(): Boolean = status == DownloadStatus.DOWNLOADING || status == DownloadStatus.VERIFYING

        /**
         * Check if the download completed successfully.
         */
        fun isCompleted(): Boolean = status == DownloadStatus.COMPLETED

        /**
         * Check if the download failed or was cancelled.
         */
        fun isFailed(): Boolean = status == DownloadStatus.FAILED || status == DownloadStatus.CANCELLED
    }

    /**
     * Listener interface for download events.
     */
    interface DownloadListener {
        /**
         * Called when a download starts.
         *
         * @param downloadId The download ID
         * @param modelId The model ID
         * @param url The download URL
         */
        fun onDownloadStarted(downloadId: String, modelId: String, url: String)

        /**
         * Called when download progress is updated.
         *
         * @param downloadId The download ID
         * @param downloadedBytes Bytes downloaded so far
         * @param totalBytes Total file size (-1 if unknown)
         * @param progress Progress percentage (0-100)
         */
        fun onDownloadProgress(downloadId: String, downloadedBytes: Long, totalBytes: Long, progress: Int)

        /**
         * Called when a download completes successfully.
         *
         * @param downloadId The download ID
         * @param modelId The model ID
         * @param filePath The local file path
         * @param fileSize The file size in bytes
         */
        fun onDownloadCompleted(downloadId: String, modelId: String, filePath: String, fileSize: Long)

        /**
         * Called when a download fails.
         *
         * @param downloadId The download ID
         * @param modelId The model ID
         * @param error The error code (see [DownloadError])
         * @param errorMessage Human-readable error message
         */
        fun onDownloadFailed(downloadId: String, modelId: String, error: Int, errorMessage: String)

        /**
         * Called when a download is paused.
         *
         * @param downloadId The download ID
         */
        fun onDownloadPaused(downloadId: String)

        /**
         * Called when a download is resumed.
         *
         * @param downloadId The download ID
         */
        fun onDownloadResumed(downloadId: String)

        /**
         * Called when a download is cancelled.
         *
         * @param downloadId The download ID
         */
        fun onDownloadCancelled(downloadId: String)
    }

    /**
     * Provider interface for custom download implementations.
     */
    interface DownloadProvider {
        /**
         * Perform a download with custom logic.
         *
         * @param url The URL to download from
         * @param destinationPath The local file path to save to
         * @param progressCallback Callback for progress updates (downloadedBytes, totalBytes)
         * @return true if download succeeded, false otherwise
         */
        fun download(
            url: String,
            destinationPath: String,
            progressCallback: (downloadedBytes: Long, totalBytes: Long) -> Unit,
        ): Boolean

        /**
         * Check if resume is supported for a URL.
         *
         * @param url The URL to check
         * @return true if the server supports range requests
         */
        fun supportsResume(url: String): Boolean
    }

    /**
     * Register the download callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgeModelPaths.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register the download callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetDownloadCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Download manager callbacks registered",
            )
        }
    }

    /**
     * Check if the download callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // DOWNLOAD CALLBACKS
    // ========================================================================

    /**
     * Start download callback.
     *
     * Starts a new download for a model.
     *
     * @param url The URL to download from
     * @param modelId The model ID
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @param priority Download priority (see [DownloadPriority])
     * @param expectedChecksum Expected checksum for verification (null to skip)
     * @return The download ID, or null if download could not be started
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun startDownloadCallback(
        url: String,
        modelId: String,
        modelType: Int,
        priority: Int,
        expectedChecksum: String?,
    ): String? {
        return try {
            // Check network connectivity first
            if (!checkNetworkConnectivity()) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "No internet connection. Please check your network settings and try again.",
                )
                // Notify listener of failure
                val downloadId = UUID.randomUUID().toString()
                try {
                    downloadListener?.onDownloadFailed(
                        downloadId,
                        modelId,
                        DownloadError.NETWORK_UNAVAILABLE,
                        "No internet connection. Please check your network settings and try again.",
                    )
                } catch (e: Exception) {
                    // Ignore listener errors
                }
                return null
            }

            // Validate URL
            try {
                URL(url)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Invalid download URL: $url",
                )
                return null
            }

            // Get destination path
            val tempPath = CppBridgeModelPaths.getTempDownloadPath(modelId)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Download destination path: $tempPath",
            )

            // Check available storage
            val availableStorage = CppBridgeModelPaths.getAvailableStorage()
            if (availableStorage < 100 * 1024 * 1024) { // Require at least 100MB free
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Low storage space: ${availableStorage / (1024 * 1024)}MB available",
                )
            }

            // Create download task
            val downloadId = UUID.randomUUID().toString()
            val task =
                DownloadTask(
                    downloadId = downloadId,
                    url = url,
                    destinationPath = tempPath,
                    modelId = modelId,
                    modelType = modelType,
                    priority = priority,
                    expectedChecksum = expectedChecksum,
                )

            activeDownloads[downloadId] = task

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting download: $downloadId for model $modelId",
            )

            // Note: Download status is tracked by the download manager, not model registry
            // The C++ registry just stores the local_path when download is complete

            // Start download on background thread
            val future =
                downloadExecutor.submit {
                    executeDownload(task)
                }
            downloadFutures[downloadId] = future

            // Notify listener
            try {
                downloadListener?.onDownloadStarted(downloadId, modelId, url)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in download listener onDownloadStarted: ${e.message}",
                )
            }

            downloadId
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to start download: ${e.message}",
            )
            null
        }
    }

    /**
     * Cancel download callback.
     *
     * Cancels an active download.
     *
     * @param downloadId The download ID to cancel
     * @return true if cancelled, false if download not found or already completed
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun cancelDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || DownloadStatus.isTerminal(task.status)) {
                return false
            }

            // Cancel the future
            val future = downloadFutures.remove(downloadId)
            future?.cancel(true)

            // Update task status
            task.status = DownloadStatus.CANCELLED
            task.error = DownloadError.CANCELLED
            task.completedAt = System.currentTimeMillis()

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Download cancelled: $downloadId",
            )

            // Clear model download status on cancellation
            CppBridgeModelRegistry.updateDownloadStatus(task.modelId, null)

            // Cleanup temp file
            try {
                File(task.destinationPath).delete()
            } catch (e: Exception) {
                // Ignore cleanup errors
            }

            // Notify listener
            try {
                downloadListener?.onDownloadCancelled(downloadId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in download listener onDownloadCancelled: ${e.message}",
                )
            }

            return true
        }
    }

    /**
     * Pause download callback.
     *
     * Pauses an active download.
     *
     * @param downloadId The download ID to pause
     * @return true if paused, false if download not found or cannot be paused
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun pauseDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || task.status != DownloadStatus.DOWNLOADING) {
                return false
            }

            // Cancel the future (will be resumed later)
            val future = downloadFutures.remove(downloadId)
            future?.cancel(true)

            task.status = DownloadStatus.PAUSED

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Download paused: $downloadId at ${task.downloadedBytes} bytes",
            )

            // Notify listener
            try {
                downloadListener?.onDownloadPaused(downloadId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in download listener onDownloadPaused: ${e.message}",
                )
            }

            return true
        }
    }

    /**
     * Resume download callback.
     *
     * Resumes a paused download.
     *
     * @param downloadId The download ID to resume
     * @return true if resumed, false if download not found or cannot be resumed
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun resumeDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || task.status != DownloadStatus.PAUSED) {
                return false
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Resuming download: $downloadId from ${task.downloadedBytes} bytes",
            )

            // Restart download on background thread
            val future =
                downloadExecutor.submit {
                    executeDownload(task, resumeFrom = task.downloadedBytes)
                }
            downloadFutures[downloadId] = future

            // Notify listener
            try {
                downloadListener?.onDownloadResumed(downloadId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in download listener onDownloadResumed: ${e.message}",
                )
            }

            return true
        }
    }

    /**
     * Get download status callback.
     *
     * Returns the current status of a download.
     *
     * @param downloadId The download ID
     * @return The download status (see [DownloadStatus]), or -1 if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDownloadStatusCallback(downloadId: String): Int {
        return activeDownloads[downloadId]?.status ?: -1
    }

    /**
     * Get download progress callback.
     *
     * Returns the download progress as a JSON string.
     *
     * @param downloadId The download ID
     * @return JSON-encoded progress information, or null if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDownloadProgressCallback(downloadId: String): String? {
        val task = activeDownloads[downloadId] ?: return null

        return buildString {
            append("{")
            append("\"download_id\":\"${escapeJson(task.downloadId)}\",")
            append("\"model_id\":\"${escapeJson(task.modelId)}\",")
            append("\"status\":${task.status},")
            append("\"error\":${task.error},")
            append("\"total_bytes\":${task.totalBytes},")
            append("\"downloaded_bytes\":${task.downloadedBytes},")
            append("\"progress\":${task.getProgress()},")
            append("\"started_at\":${task.startedAt},")
            append("\"completed_at\":${task.completedAt}")
            append("}")
        }
    }

    /**
     * Get all active downloads callback.
     *
     * Returns information about all active downloads.
     *
     * @return JSON-encoded array of download information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAllDownloadsCallback(): String {
        val downloads = activeDownloads.values.toList()

        return buildString {
            append("[")
            downloads.forEachIndexed { index, task ->
                if (index > 0) append(",")
                append("{")
                append("\"download_id\":\"${escapeJson(task.downloadId)}\",")
                append("\"model_id\":\"${escapeJson(task.modelId)}\",")
                append("\"url\":\"${escapeJson(task.url)}\",")
                append("\"status\":${task.status},")
                append("\"error\":${task.error},")
                append("\"total_bytes\":${task.totalBytes},")
                append("\"downloaded_bytes\":${task.downloadedBytes},")
                append("\"progress\":${task.getProgress()}")
                append("}")
            }
            append("]")
        }
    }

    /**
     * Get active download count callback.
     *
     * @return The number of active downloads
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getActiveDownloadCountCallback(): Int {
        return activeDownloads.values.count { it.isActive() }
    }

    /**
     * Clear completed downloads callback.
     *
     * Removes completed, failed, and cancelled downloads from tracking.
     *
     * @return The number of downloads cleared
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearCompletedDownloadsCallback(): Int {
        val toRemove = activeDownloads.filter { DownloadStatus.isTerminal(it.value.status) }
        toRemove.keys.forEach { activeDownloads.remove(it) }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Cleared ${toRemove.size} completed downloads",
        )

        return toRemove.size
    }

    // ========================================================================
    // DOWNLOAD EXECUTION
    // ========================================================================

    /**
     * Execute a download task.
     */
    private fun executeDownload(task: DownloadTask, resumeFrom: Long = 0L) {
        var connection: HttpURLConnection? = null
        var inputStream: InputStream? = null
        var outputStream: FileOutputStream? = null

        try {
            task.status = DownloadStatus.DOWNLOADING

            // Check for custom provider
            val provider = downloadProvider
            if (provider != null) {
                val downloadedBytes = AtomicLong(resumeFrom)
                val success =
                    provider.download(
                        task.url,
                        task.destinationPath,
                    ) { bytes, total ->
                        downloadedBytes.set(bytes)
                        task.downloadedBytes = bytes
                        task.totalBytes = total
                        notifyProgress(task)
                    }

                if (success) {
                    completeDownload(task)
                } else {
                    failDownload(task, DownloadError.UNKNOWN, "Custom provider download failed")
                }
                return
            }

            // Standard download using HttpURLConnection
            val url = URL(task.url)
            connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = DEFAULT_CONNECT_TIMEOUT_MS
            connection.readTimeout = DEFAULT_READ_TIMEOUT_MS
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK/Kotlin")

            // Support resume if possible
            if (resumeFrom > 0) {
                connection.setRequestProperty("Range", "bytes=$resumeFrom-")
            }

            connection.connect()

            val responseCode = connection.responseCode
            when {
                responseCode == HttpURLConnection.HTTP_OK -> {
                    task.totalBytes = connection.contentLengthLong
                    task.downloadedBytes = 0L
                }
                responseCode == HttpURLConnection.HTTP_PARTIAL -> {
                    // Resume successful
                    val contentRange = connection.getHeaderField("Content-Range")
                    if (contentRange != null && contentRange.contains("/")) {
                        val total = contentRange.substringAfter("/").toLongOrNull()
                        if (total != null) {
                            task.totalBytes = total
                        }
                    }
                    task.downloadedBytes = resumeFrom
                }
                responseCode in 400..599 -> {
                    failDownload(task, DownloadError.SERVER_ERROR, "Server returned $responseCode")
                    return
                }
                else -> {
                    failDownload(task, DownloadError.NETWORK_ERROR, "Unexpected response: $responseCode")
                    return
                }
            }

            // Ensure parent directory exists
            val destFile = File(task.destinationPath)
            destFile.parentFile?.mkdirs()

            inputStream = connection.inputStream
            outputStream = FileOutputStream(destFile, resumeFrom > 0)

            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var bytesRead: Int
            var lastProgressUpdate = System.currentTimeMillis()

            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                // Check for cancellation
                if (Thread.currentThread().isInterrupted || task.status == DownloadStatus.CANCELLED) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Download interrupted: ${task.downloadId}",
                    )
                    return
                }

                // Check for pause
                if (task.status == DownloadStatus.PAUSED) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Download paused during execution: ${task.downloadId}",
                    )
                    return
                }

                outputStream.write(buffer, 0, bytesRead)
                task.downloadedBytes += bytesRead

                // Throttle progress updates (max once per 100ms)
                val now = System.currentTimeMillis()
                if (now - lastProgressUpdate >= 100) {
                    notifyProgress(task)
                    lastProgressUpdate = now
                }
            }

            outputStream.flush()

            // Verify checksum if provided
            if (task.expectedChecksum != null) {
                task.status = DownloadStatus.VERIFYING
                if (!verifyChecksum(task.destinationPath, task.expectedChecksum)) {
                    failDownload(task, DownloadError.CHECKSUM_FAILED, "Checksum verification failed")
                    return
                }
            }

            // Complete download
            completeDownload(task)
        } catch (e: java.net.SocketTimeoutException) {
            failDownload(task, DownloadError.TIMEOUT, DownloadError.getUserMessage(DownloadError.TIMEOUT))
        } catch (e: java.net.UnknownHostException) {
            // DNS resolution failed - likely no internet or DNS issue
            val userMessage =
                if (!checkNetworkConnectivity()) {
                    DownloadError.getUserMessage(DownloadError.NETWORK_UNAVAILABLE)
                } else {
                    DownloadError.getUserMessage(DownloadError.DNS_ERROR)
                }
            failDownload(task, DownloadError.DNS_ERROR, userMessage)
        } catch (e: java.net.ConnectException) {
            // Connection refused or network unreachable
            val userMessage =
                if (!checkNetworkConnectivity()) {
                    DownloadError.getUserMessage(DownloadError.NETWORK_UNAVAILABLE)
                } else {
                    DownloadError.getUserMessage(DownloadError.NETWORK_ERROR)
                }
            failDownload(task, DownloadError.NETWORK_ERROR, userMessage)
        } catch (e: java.net.NoRouteToHostException) {
            failDownload(task, DownloadError.NETWORK_UNAVAILABLE, DownloadError.getUserMessage(DownloadError.NETWORK_UNAVAILABLE))
        } catch (e: javax.net.ssl.SSLException) {
            failDownload(task, DownloadError.SSL_ERROR, DownloadError.getUserMessage(DownloadError.SSL_ERROR))
        } catch (e: java.io.IOException) {
            if (Thread.currentThread().isInterrupted) {
                // Download was cancelled/paused
                return
            }
            // Check if this is a network-related IO error
            val errorMessage = e.message?.lowercase() ?: ""
            val (errorCode, userMessage) =
                when {
                    errorMessage.contains("network") || errorMessage.contains("connection") -> {
                        if (!checkNetworkConnectivity()) {
                            Pair(DownloadError.NETWORK_UNAVAILABLE, DownloadError.getUserMessage(DownloadError.NETWORK_UNAVAILABLE))
                        } else {
                            Pair(DownloadError.NETWORK_ERROR, DownloadError.getUserMessage(DownloadError.NETWORK_ERROR))
                        }
                    }
                    errorMessage.contains("space") || errorMessage.contains("storage") -> {
                        Pair(DownloadError.INSUFFICIENT_STORAGE, DownloadError.getUserMessage(DownloadError.INSUFFICIENT_STORAGE))
                    }
                    else -> {
                        Pair(DownloadError.FILE_ERROR, DownloadError.getUserMessage(DownloadError.FILE_ERROR))
                    }
                }
            failDownload(task, errorCode, userMessage)
        } catch (e: Exception) {
            if (Thread.currentThread().isInterrupted) {
                return
            }
            failDownload(task, DownloadError.UNKNOWN, DownloadError.getUserMessage(DownloadError.UNKNOWN))
        } finally {
            try {
                inputStream?.close()
            } catch (e: Exception) {
                // Ignore
            }
            try {
                outputStream?.close()
            } catch (e: Exception) {
                // Ignore
            }
            connection?.disconnect()
        }
    }

    /**
     * Complete a download successfully.
     */
    private fun completeDownload(task: DownloadTask) {
        task.status = DownloadStatus.COMPLETED
        task.completedAt = System.currentTimeMillis()

        // Get file size
        val fileSize = File(task.destinationPath).length()
        task.downloadedBytes = fileSize
        if (task.totalBytes < 0) {
            task.totalBytes = fileSize
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Download completed: ${task.downloadId} (${fileSize / 1024}KB)",
        )

        // Move to final location
        val moved =
            CppBridgeModelPaths.moveDownloadToFinal(
                task.destinationPath,
                task.modelId,
                task.modelType,
            )

        if (moved) {
            // Update model download status in C++ registry with local path
            val finalPath = CppBridgeModelPaths.getModelPath(task.modelId, task.modelType)
            CppBridgeModelRegistry.updateDownloadStatus(task.modelId, finalPath)

            // Notify listener
            try {
                downloadListener?.onDownloadCompleted(task.downloadId, task.modelId, finalPath, fileSize)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in download listener onDownloadCompleted: ${e.message}",
                )
            }
        } else {
            failDownload(task, DownloadError.FILE_ERROR, "Failed to move download to final location")
        }
    }

    /**
     * Fail a download with an error.
     */
    private fun failDownload(task: DownloadTask, error: Int, message: String) {
        task.status = DownloadStatus.FAILED
        task.error = error
        task.completedAt = System.currentTimeMillis()

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.ERROR,
            TAG,
            "Download failed: ${task.downloadId} - $message",
        )

        // Clear download status on failure (model is no longer downloaded)
        CppBridgeModelRegistry.updateDownloadStatus(task.modelId, null)

        // Cleanup temp file
        try {
            File(task.destinationPath).delete()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }

        // Notify listener
        try {
            downloadListener?.onDownloadFailed(task.downloadId, task.modelId, error, message)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in download listener onDownloadFailed: ${e.message}",
            )
        }
    }

    /**
     * Notify progress update.
     */
    private fun notifyProgress(task: DownloadTask) {
        try {
            downloadListener?.onDownloadProgress(
                task.downloadId,
                task.downloadedBytes,
                task.totalBytes,
                task.getProgress(),
            )
        } catch (e: Exception) {
            // Ignore progress listener errors
        }

        // Note: C++ progress callback not used - downloads are managed entirely in Kotlin
        // The progress is reported through downloadListener to the SDK's Flow-based API
    }

    /**
     * Verify file checksum.
     */
    private fun verifyChecksum(filePath: String, expectedChecksum: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val digest = java.security.MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }

            val actualChecksum = digest.digest().joinToString("") { "%02x".format(it) }
            val matches = actualChecksum.equals(expectedChecksum, ignoreCase = true)

            if (!matches) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Checksum mismatch: expected=$expectedChecksum, actual=$actualChecksum",
                )
            }

            matches
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Checksum verification error: ${e.message}",
            )
            false
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the download callbacks with C++ core.
     *
     * Registers [startDownloadCallback], [cancelDownloadCallback],
     * [pauseDownloadCallback], [resumeDownloadCallback], etc. with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_download_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetDownloadCallbacks()

    /**
     * Native method to unset the download callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_download_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetDownloadCallbacks()

    // Note: nativeInvokeProgressCallback removed - downloads are managed entirely in Kotlin
    // Progress is reported through downloadListener to the SDK's Flow-based API

    /**
     * Native method to start a download from C++.
     *
     * @param url The URL to download
     * @param modelId The model ID
     * @param modelType The model type
     * @param priority Download priority
     * @param expectedChecksum Expected checksum (or null)
     * @return The download ID, or null on error
     *
     * C API: rac_download_start(url, model_id, type, priority, checksum)
     */
    @JvmStatic
    external fun nativeStartDownload(
        url: String,
        modelId: String,
        modelType: Int,
        priority: Int,
        expectedChecksum: String?,
    ): String?

    /**
     * Native method to cancel a download from C++.
     *
     * @param downloadId The download ID
     * @return 0 on success, error code on failure
     *
     * C API: rac_download_cancel(download_id)
     */
    @JvmStatic
    external fun nativeCancel(downloadId: String): Int

    /**
     * Native method to pause a download from C++.
     *
     * @param downloadId The download ID
     * @return 0 on success, error code on failure
     *
     * C API: rac_download_pause(download_id)
     */
    @JvmStatic
    external fun nativePause(downloadId: String): Int

    /**
     * Native method to resume a download from C++.
     *
     * @param downloadId The download ID
     * @return 0 on success, error code on failure
     *
     * C API: rac_download_resume(download_id)
     */
    @JvmStatic
    external fun nativeResume(downloadId: String): Int

    /**
     * Native method to get download status from C++.
     *
     * @param downloadId The download ID
     * @return Download status, or -1 if not found
     *
     * C API: rac_download_get_status(download_id)
     */
    @JvmStatic
    external fun nativeGetStatus(downloadId: String): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the download callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetDownloadCallbacks()

            downloadListener = null
            downloadProvider = null
            isRegistered = false
        }
    }

    /**
     * Shutdown the download manager.
     *
     * Cancels all active downloads and releases resources.
     */
    fun shutdown() {
        synchronized(lock) {
            unregister()

            // Cancel all active downloads
            activeDownloads.values
                .filter { it.isActive() }
                .forEach { task ->
                    cancelDownloadCallback(task.downloadId)
                }

            // Shutdown executor
            try {
                downloadExecutor.shutdown()
                if (!downloadExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                    downloadExecutor.shutdownNow()
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error shutting down download executor: ${e.message}",
                )
                downloadExecutor.shutdownNow()
            }

            activeDownloads.clear()
            downloadFutures.clear()
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Start a download for a model.
     *
     * @param url The URL to download from
     * @param modelId The model ID
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @param priority Download priority (see [DownloadPriority])
     * @param expectedChecksum Expected checksum for verification (null to skip)
     * @return The download ID, or null if download could not be started
     */
    fun startDownload(
        url: String,
        modelId: String,
        modelType: Int,
        priority: Int = DownloadPriority.NORMAL,
        expectedChecksum: String? = null,
    ): String? {
        return startDownloadCallback(url, modelId, modelType, priority, expectedChecksum)
    }

    /**
     * Cancel a download.
     *
     * @param downloadId The download ID
     * @return true if cancelled
     */
    fun cancelDownload(downloadId: String): Boolean {
        return cancelDownloadCallback(downloadId)
    }

    /**
     * Pause a download.
     *
     * @param downloadId The download ID
     * @return true if paused
     */
    fun pauseDownload(downloadId: String): Boolean {
        return pauseDownloadCallback(downloadId)
    }

    /**
     * Resume a download.
     *
     * @param downloadId The download ID
     * @return true if resumed
     */
    fun resumeDownload(downloadId: String): Boolean {
        return resumeDownloadCallback(downloadId)
    }

    /**
     * Get the status of a download.
     *
     * @param downloadId The download ID
     * @return The download status, or -1 if not found
     */
    fun getDownloadStatus(downloadId: String): Int {
        return getDownloadStatusCallback(downloadId)
    }

    /**
     * Get a download task by ID.
     *
     * @param downloadId The download ID
     * @return The [DownloadTask], or null if not found
     */
    fun getDownload(downloadId: String): DownloadTask? {
        return activeDownloads[downloadId]
    }

    /**
     * Get all active downloads.
     *
     * @return List of active [DownloadTask] instances
     */
    fun getActiveDownloads(): List<DownloadTask> {
        return activeDownloads.values.filter { it.isActive() }
    }

    /**
     * Get all downloads.
     *
     * @return List of all [DownloadTask] instances
     */
    fun getAllDownloads(): List<DownloadTask> {
        return activeDownloads.values.toList()
    }

    /**
     * Get the number of active downloads.
     *
     * @return Active download count
     */
    fun getActiveDownloadCount(): Int {
        return getActiveDownloadCountCallback()
    }

    /**
     * Clear completed downloads from tracking.
     *
     * @return Number of downloads cleared
     */
    fun clearCompletedDownloads(): Int {
        return clearCompletedDownloadsCallback()
    }

    /**
     * Cancel all active downloads.
     *
     * @return Number of downloads cancelled
     */
    fun cancelAllDownloads(): Int {
        val activeIds =
            activeDownloads.values
                .filter { it.isActive() }
                .map { it.downloadId }

        var cancelled = 0
        for (downloadId in activeIds) {
            if (cancelDownloadCallback(downloadId)) {
                cancelled++
            }
        }

        return cancelled
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    // ========================================================================
    // NETWORK CONNECTIVITY
    // ========================================================================

    /**
     * Check if network connectivity is available.
     *
     * On Android, uses ConnectivityManager to check network state.
     * On JVM, attempts a simple connection check.
     *
     * @return true if network is available, false otherwise
     */
    private fun checkNetworkConnectivity(): Boolean {
        return try {
            // Try to use Android's NetworkConnectivity if available
            val networkClass = Class.forName("com.runanywhere.sdk.platform.NetworkConnectivity")
            val isAvailableMethod = networkClass.getDeclaredMethod("isNetworkAvailable")
            val instance = networkClass.getDeclaredField("INSTANCE").get(null)
            isAvailableMethod.invoke(instance) as Boolean
        } catch (e: ClassNotFoundException) {
            // Not on Android, assume network is available (will fail with proper error if not)
            true
        } catch (e: Exception) {
            // If we can't check, assume available and let it fail with proper error message
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Could not check network connectivity: ${e.message}",
            )
            true
        }
    }

    /**
     * Check network connectivity and return detailed status.
     *
     * @return Pair of (isAvailable, statusMessage)
     */
    fun checkNetworkStatus(): Pair<Boolean, String> {
        return try {
            val networkClass = Class.forName("com.runanywhere.sdk.platform.NetworkConnectivity")
            val isAvailableMethod = networkClass.getDeclaredMethod("isNetworkAvailable")
            val getDescriptionMethod = networkClass.getDeclaredMethod("getNetworkDescription")
            val instance = networkClass.getDeclaredField("INSTANCE").get(null)

            val isAvailable = isAvailableMethod.invoke(instance) as Boolean
            val description = getDescriptionMethod.invoke(instance) as String

            Pair(isAvailable, description)
        } catch (e: Exception) {
            Pair(true, "Unknown")
        }
    }
}
