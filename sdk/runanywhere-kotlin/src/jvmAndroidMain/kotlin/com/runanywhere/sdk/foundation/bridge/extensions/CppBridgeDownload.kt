/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Download extension for CppBridge.
 *
 * v2 close-out Phase H. Previously this file carried ~1.3 KLOC of
 * HttpURLConnection transport, retry/resume state, chunked progress
 * accounting, and SHA-256 verification. All of that now lives in
 * runanywhere-commons behind the `rac_http_download_execute` C ABI
 * (see include/rac/infrastructure/http/rac_http_download.h). This
 * file is the thin Kotlin shim that:
 *
 *   1. Owns task lifecycle (id → status/progress bookkeeping,
 *      listener dispatch, cancellation flag).
 *   2. Runs each download on an executor thread that calls
 *      `RunAnywhereBridge.racHttpDownloadExecute(...)` and forwards
 *      progress to the Kotlin `DownloadListener`.
 *   3. Maps `RAC_HTTP_DL_*` result codes to the Kotlin
 *      `DownloadError.*` constants (they are byte-for-byte equal, see
 *      rac_http_download.h).
 *
 * The native code handles HTTP transport, retry, redirect,
 * checksum verification, and file I/O — see Phase H for details.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.NativeDownloadProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Download bridge that exposes a simple Kotlin surface on top of the
 * native downloader in runanywhere-commons.
 *
 * Usage: set [downloadListener] before calling [startDownload]. All
 * progress and completion events fire on the executor thread.
 */
object CppBridgeDownload {
    /**
     * Download status constants matching the C++
     * `RAC_DOWNLOAD_STATUS_*` values in rac_download.h. Kept as-is
     * for API compatibility with existing SDK consumers.
     */
    object DownloadStatus {
        const val QUEUED = 0
        const val DOWNLOADING = 1
        const val PAUSED = 2
        const val COMPLETED = 3
        const val FAILED = 4
        const val CANCELLED = 5
        const val VERIFYING = 6

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

        fun isTerminal(status: Int): Boolean = status in listOf(COMPLETED, FAILED, CANCELLED)
    }

    /**
     * Download error codes matching the `RAC_HTTP_DL_*` enum in
     * rac_http_download.h byte-for-byte. When you change one side,
     * change the other.
     */
    object DownloadError {
        const val NONE = 0
        const val NETWORK_ERROR = 1
        const val FILE_ERROR = 2
        const val INSUFFICIENT_STORAGE = 3
        const val INVALID_URL = 4
        const val CHECKSUM_FAILED = 5
        const val CANCELLED = 6
        const val SERVER_ERROR = 7
        const val TIMEOUT = 8
        const val NETWORK_UNAVAILABLE = 9
        const val DNS_ERROR = 10
        const val SSL_ERROR = 11
        const val UNKNOWN = 99

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
     * Download priority hint. Native transport ignores this today —
     * priorities are honored only by ordering executor submissions.
     */
    object DownloadPriority {
        const val LOW = 0
        const val NORMAL = 1
        const val HIGH = 2
        const val URGENT = 3
    }

    private const val TAG = "CppBridgeDownload"

    // Timeout applied to every native download (matches the previous
    // HttpURLConnection read timeout).
    private const val DEFAULT_READ_TIMEOUT_MS = 60_000

    // Minimum MB of free storage before we warn the caller — same
    // threshold as the pre-Phase-H implementation.
    private const val LOW_STORAGE_WARN_MB = 100L

    private const val MAX_CONCURRENT_DOWNLOADS = 3

    private val downloadExecutor =
        Executors.newFixedThreadPool(MAX_CONCURRENT_DOWNLOADS) { runnable ->
            Thread(runnable, "runanywhere-download").apply { isDaemon = true }
        }

    private val activeDownloads = ConcurrentHashMap<String, DownloadTask>()
    private val downloadFutures = ConcurrentHashMap<String, Future<*>>()
    private val downloadLock = Any()

    /** Global listener for all download events; nullable. */
    @Volatile
    var downloadListener: DownloadListener? = null

    /**
     * Optional provider SPI. When non-null, takes precedence over
     * the native downloader — consumers can plug in their own
     * OkHttp / Retrofit / etc. implementation if they need to.
     *
     * Round 1 KOTLIN (G-A5): default is now `null`, so the libcurl
     * JNI path (`racHttpDownloadExecute`) is used by default. The
     * legacy `HttpURLConnectionDownloadProvider` was DELETED — it
     * was the source of the commons-HTTP bypass on Android.
     */
    @Volatile
    var downloadProvider: DownloadProvider? = null

    /**
     * Per-download state. `status` / `error` / `*Bytes` are
     * @Volatile because they're updated from the executor thread and
     * read from both the cancel/pause path and external inspectors.
     */
    data class DownloadTask(
        val downloadId: String,
        val url: String,
        val destinationPath: String,
        val modelId: String,
        /**
         * Inference framework for this download (int matching
         * [CppBridgeModelRegistry.Framework]). Used to compute the final
         * `{base}/RunAnywhere/Models/{framework}/{modelId}/` path.
         */
        val framework: Int,
        @Volatile var status: Int = DownloadStatus.QUEUED,
        @Volatile var error: Int = DownloadError.NONE,
        @Volatile var totalBytes: Long = -1L,
        @Volatile var downloadedBytes: Long = 0L,
        val startedAt: Long = System.currentTimeMillis(),
        @Volatile var completedAt: Long = 0L,
        val priority: Int = DownloadPriority.NORMAL,
        val expectedChecksum: String? = null,
    ) {
        fun getProgress(): Int {
            if (totalBytes <= 0) return 0
            return ((downloadedBytes * 100) / totalBytes).toInt().coerceIn(0, 100)
        }

        fun getStatusName(): String = DownloadStatus.getName(status)

        fun getErrorName(): String = DownloadError.getName(error)

        fun isActive(): Boolean =
            status == DownloadStatus.DOWNLOADING || status == DownloadStatus.VERIFYING

        fun isCompleted(): Boolean = status == DownloadStatus.COMPLETED

        fun isFailed(): Boolean =
            status == DownloadStatus.FAILED || status == DownloadStatus.CANCELLED
    }

    /** Observer hook for UI + orchestration layers. */
    interface DownloadListener {
        fun onDownloadStarted(downloadId: String, modelId: String, url: String)

        fun onDownloadProgress(downloadId: String, downloadedBytes: Long, totalBytes: Long, progress: Int)

        fun onDownloadCompleted(downloadId: String, modelId: String, filePath: String, fileSize: Long)

        fun onDownloadFailed(downloadId: String, modelId: String, error: Int, errorMessage: String)

        fun onDownloadPaused(downloadId: String)

        fun onDownloadResumed(downloadId: String)

        fun onDownloadCancelled(downloadId: String)
    }

    /**
     * Alternative transport. Implement this and assign to
     * [downloadProvider] to override the native libcurl path.
     */
    interface DownloadProvider {
        fun download(
            url: String,
            destinationPath: String,
            progressCallback: (downloadedBytes: Long, totalBytes: Long) -> Unit,
        ): Boolean

        fun supportsResume(url: String): Boolean
    }

    // ========================================================================
    // PUBLIC API
    // ========================================================================

    /**
     * Start a fresh download. Returns the generated download ID, or
     * null when the preflight (network availability, URL validity,
     * temp path resolution) failed.
     */
    fun startDownload(
        url: String,
        modelId: String,
        /** Inference framework int (see [CppBridgeModelRegistry.Framework]). */
        framework: Int,
        priority: Int = DownloadPriority.NORMAL,
        expectedChecksum: String? = null,
    ): String? = startDownloadCallback(url, modelId, framework, priority, expectedChecksum)

    fun cancelDownload(downloadId: String): Boolean = cancelDownloadCallback(downloadId)

    fun pauseDownload(downloadId: String): Boolean = pauseDownloadCallback(downloadId)

    fun resumeDownload(downloadId: String): Boolean = resumeDownloadCallback(downloadId)

    fun getDownloadStatus(downloadId: String): Int = getDownloadStatusCallback(downloadId)

    fun getDownload(downloadId: String): DownloadTask? = activeDownloads[downloadId]

    fun getActiveDownloads(): List<DownloadTask> =
        activeDownloads.values.filter { it.isActive() }

    fun getAllDownloads(): List<DownloadTask> = activeDownloads.values.toList()

    fun getActiveDownloadCount(): Int = getActiveDownloadCountCallback()

    fun clearCompletedDownloads(): Int = clearCompletedDownloadsCallback()

    fun cancelAllDownloads(): Int {
        val activeIds = activeDownloads.values.filter { it.isActive() }.map { it.downloadId }
        var cancelled = 0
        for (id in activeIds) {
            if (cancelDownloadCallback(id)) cancelled++
        }
        return cancelled
    }

    /**
     * Preflight network status. Delegates to
     * `com.runanywhere.sdk.platform.NetworkConnectivity` via
     * reflection when available (Android ConnectivityManager path);
     * on plain JVM returns `(true, "Unknown")` and lets the native
     * download itself surface any connectivity issues.
     */
    fun checkNetworkStatus(): Pair<Boolean, String> {
        return try {
            val cls = Class.forName("com.runanywhere.sdk.platform.NetworkConnectivity")
            val inst = cls.getDeclaredField("INSTANCE").get(null)
            val available = cls.getDeclaredMethod("isNetworkAvailable").invoke(inst) as Boolean
            val description = cls.getDeclaredMethod("getNetworkDescription").invoke(inst) as String
            available to description
        } catch (e: Exception) {
            true to "Unknown"
        }
    }

    // ========================================================================
    // JVM-STATIC CALLBACKS
    //
    // These mirror the names used historically for Phase 2 C++ bridge
    // registration. Kept so any caller that reached in by name still
    // resolves. The bodies are the private helpers below.
    // ========================================================================

    @JvmStatic
    fun startDownloadCallback(
        url: String,
        modelId: String,
        framework: Int,
        priority: Int,
        expectedChecksum: String?,
    ): String? {
        return try {
            if (!checkNetworkStatus().first) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "No internet connection. Please check your network settings and try again.",
                )
                notifyListenerFailed(
                    downloadId = UUID.randomUUID().toString(),
                    modelId = modelId,
                    error = DownloadError.NETWORK_UNAVAILABLE,
                    message = DownloadError.getUserMessage(DownloadError.NETWORK_UNAVAILABLE),
                )
                return null
            }

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

            val tempPath = CppBridgeModelPaths.getTempDownloadPath(modelId)
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Download destination path: $tempPath",
            )

            val availableStorage = CppBridgeModelPaths.getAvailableStorage()
            if (availableStorage < LOW_STORAGE_WARN_MB * 1024 * 1024) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Low storage space: ${availableStorage / (1024 * 1024)}MB available",
                )
            }

            val downloadId = UUID.randomUUID().toString()
            val task =
                DownloadTask(
                    downloadId = downloadId,
                    url = url,
                    destinationPath = tempPath,
                    modelId = modelId,
                    framework = framework,
                    priority = priority,
                    expectedChecksum = expectedChecksum,
                )
            activeDownloads[downloadId] = task

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting download: $downloadId for model $modelId",
            )

            val future = downloadExecutor.submit { executeDownload(task) }
            downloadFutures[downloadId] = future

            safeInvoke { downloadListener?.onDownloadStarted(downloadId, modelId, url) }
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

    @JvmStatic
    fun cancelDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || DownloadStatus.isTerminal(task.status)) return false

            // Flip the status flag — the native runner's progress
            // listener checks this on every chunk and returns false,
            // which aborts libcurl.
            task.status = DownloadStatus.CANCELLED
            task.error = DownloadError.CANCELLED
            task.completedAt = System.currentTimeMillis()

            // Also interrupt the worker thread so it bails out of any
            // non-libcurl wait (e.g. verify phase).
            downloadFutures.remove(downloadId)?.cancel(true)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Download cancelled: $downloadId",
            )

            CppBridgeModelRegistry.updateDownloadStatus(task.modelId, null)
            runCatching { File(task.destinationPath).delete() }

            safeInvoke { downloadListener?.onDownloadCancelled(downloadId) }
            return true
        }
    }

    @JvmStatic
    fun pauseDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || task.status != DownloadStatus.DOWNLOADING) return false

            task.status = DownloadStatus.PAUSED
            downloadFutures.remove(downloadId)?.cancel(true)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Download paused: $downloadId at ${task.downloadedBytes} bytes",
            )

            safeInvoke { downloadListener?.onDownloadPaused(downloadId) }
            return true
        }
    }

    @JvmStatic
    fun resumeDownloadCallback(downloadId: String): Boolean {
        synchronized(downloadLock) {
            val task = activeDownloads[downloadId]
            if (task == null || task.status != DownloadStatus.PAUSED) return false

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Resuming download: $downloadId from ${task.downloadedBytes} bytes",
            )

            val future = downloadExecutor.submit { executeDownload(task, resumeFrom = task.downloadedBytes) }
            downloadFutures[downloadId] = future

            safeInvoke { downloadListener?.onDownloadResumed(downloadId) }
            return true
        }
    }

    @JvmStatic
    fun getDownloadStatusCallback(downloadId: String): Int =
        activeDownloads[downloadId]?.status ?: -1

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

    @JvmStatic
    fun getActiveDownloadCountCallback(): Int =
        activeDownloads.values.count { it.isActive() }

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
    // INTERNAL: download execution
    // ========================================================================

    /**
     * Drive one download through the native runner. Called on an
     * executor thread. `resumeFrom > 0` means append-and-resume.
     */
    private fun executeDownload(task: DownloadTask, resumeFrom: Long = 0L) {
        try {
            task.status = DownloadStatus.DOWNLOADING

            // Custom SPI wins. If the host app supplied a provider,
            // we hand off — e.g. an enterprise OkHttp with custom
            // interceptors / proxies. The provider is responsible for
            // checksum verification on its side.
            downloadProvider?.let { provider ->
                val success =
                    provider.download(task.url, task.destinationPath) { bytes, total ->
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

            // Native libcurl runner via JNI.
            val listener =
                NativeDownloadProgressListener { bytes, total ->
                    // Cancellation: pause or cancel → tell libcurl to stop.
                    val s = task.status
                    if (s == DownloadStatus.CANCELLED || s == DownloadStatus.PAUSED) {
                        return@NativeDownloadProgressListener false
                    }
                    task.downloadedBytes = bytes
                    if (total > 0) task.totalBytes = total
                    notifyProgress(task)
                    true
                }

            val outStatus = IntArray(1)
            val rc =
                RunAnywhereBridge.racHttpDownloadExecute(
                    url = task.url,
                    destPath = task.destinationPath,
                    expectedSha256Hex = task.expectedChecksum,
                    resumeFromByte = resumeFrom,
                    timeoutMs = DEFAULT_READ_TIMEOUT_MS,
                    listener = listener,
                    outHttpStatus = outStatus,
                )

            when (rc) {
                DownloadError.NONE -> completeDownload(task)
                DownloadError.CANCELLED -> {
                    // Cancelled path: user-initiated cancel or pause.
                    // If PAUSED, leave task.status untouched for resume
                    // to pick it up; otherwise the cancel flow in
                    // cancelDownloadCallback already fired the listener.
                }
                else -> failDownload(task, rc, DownloadError.getUserMessage(rc))
            }
        } catch (e: Exception) {
            if (Thread.currentThread().isInterrupted) return
            failDownload(
                task,
                DownloadError.UNKNOWN,
                e.message ?: DownloadError.getUserMessage(DownloadError.UNKNOWN),
            )
        }
    }

    private fun completeDownload(task: DownloadTask) {
        task.status = DownloadStatus.COMPLETED
        task.completedAt = System.currentTimeMillis()

        val fileSize = runCatching { File(task.destinationPath).length() }.getOrDefault(0L)
        task.downloadedBytes = fileSize
        if (task.totalBytes < 0) task.totalBytes = fileSize

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Download completed: ${task.downloadId} (${fileSize / 1024}KB)",
        )

        val moved =
            CppBridgeModelPaths.moveDownloadToFinal(
                task.destinationPath,
                task.modelId,
                task.framework,
            )

        if (moved) {
            val finalPath = CppBridgeModelPaths.getModelPath(task.modelId, task.framework)
            CppBridgeModelRegistry.updateDownloadStatus(task.modelId, finalPath)
            safeInvoke {
                downloadListener?.onDownloadCompleted(task.downloadId, task.modelId, finalPath, fileSize)
            }
        } else {
            failDownload(task, DownloadError.FILE_ERROR, "Failed to move download to final location")
        }
    }

    private fun failDownload(task: DownloadTask, error: Int, message: String) {
        task.status = DownloadStatus.FAILED
        task.error = error
        task.completedAt = System.currentTimeMillis()

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.ERROR,
            TAG,
            "Download failed: ${task.downloadId} - $message",
        )

        CppBridgeModelRegistry.updateDownloadStatus(task.modelId, null)
        runCatching { File(task.destinationPath).delete() }

        safeInvoke { downloadListener?.onDownloadFailed(task.downloadId, task.modelId, error, message) }
    }

    private fun notifyProgress(task: DownloadTask) {
        safeInvoke {
            downloadListener?.onDownloadProgress(
                task.downloadId,
                task.downloadedBytes,
                task.totalBytes,
                task.getProgress(),
            )
        }
    }

    private fun notifyListenerFailed(downloadId: String, modelId: String, error: Int, message: String) {
        safeInvoke { downloadListener?.onDownloadFailed(downloadId, modelId, error, message) }
    }

    private inline fun safeInvoke(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Download listener threw: ${e.message}",
            )
        }
    }

    private fun escapeJson(value: String): String =
        value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
}

// Round 1 KOTLIN (G-A5): `HttpURLConnectionDownloadProvider` DELETED.
// The legacy hand-rolled `HttpURLConnection` transport was the
// commons-HTTP bypass; the libcurl JNI path (`racHttpDownloadExecute`)
// is now the default for all Kotlin/Android downloads.
