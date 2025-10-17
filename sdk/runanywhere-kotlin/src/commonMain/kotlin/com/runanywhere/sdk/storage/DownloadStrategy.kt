package com.runanywhere.sdk.storage

import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.flow.Flow

/**
 * Download strategy interface matching iOS DownloadStrategy protocol
 * Base interface for all download operations, extended by ModelStorageStrategy
 */
interface DownloadStrategy {

    /**
     * Download a model with progress tracking
     * @param model The model to download
     * @param destinationFolder The destination folder for the download
     * @param progressHandler Progress callback with DownloadProgress updates
     * @return The path to the downloaded model
     */
    suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((DownloadProgress) -> Unit)? = null
    ): String

    /**
     * Check if this strategy can handle downloading the given model
     */
    fun canHandle(model: ModelInfo): Boolean

    /**
     * Get estimated download size for the model
     */
    suspend fun getEstimatedSize(model: ModelInfo): Long?

    /**
     * Cancel an ongoing download
     */
    suspend fun cancelDownload(model: ModelInfo): Boolean
}

/**
 * Download progress information matching iOS DownloadProgress struct
 * Provides comprehensive progress tracking with metadata
 */
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val estimatedTimeRemaining: Double? = null,
    val currentFile: String? = null,
    val filesDownloaded: Int = 0,
    val totalFiles: Int = 1
) {
    /**
     * Progress percentage (0.0 to 1.0)
     */
    val percentage: Double
        get() = if (totalBytes > 0) {
            bytesDownloaded.toDouble() / totalBytes.toDouble()
        } else {
            0.0
        }

    /**
     * File-based progress percentage (for multi-file downloads)
     */
    val fileProgress: Double
        get() = if (totalFiles > 0) {
            filesDownloaded.toDouble() / totalFiles.toDouble()
        } else {
            0.0
        }

    /**
     * Whether download is complete
     */
    val isComplete: Boolean
        get() = state == DownloadState.COMPLETED

    /**
     * Whether download has failed
     */
    val hasFailed: Boolean
        get() = state == DownloadState.FAILED
}

/**
 * Download state enumeration matching iOS patterns
 */
enum class DownloadState {
    PENDING,
    DOWNLOADING,
    COMPLETED,
    FAILED,
    CANCELLED,
    PAUSED
}

/**
 * Download error hierarchy matching iOS DownloadError enum
 * Provides comprehensive error categorization with detailed information
 */
sealed class DownloadError : Exception() {

    // URL and request errors
    data class InvalidURL(val url: String) : DownloadError() {
        override val message = "Invalid URL: $url"
    }

    // Network-related errors
    data class NetworkError(override val cause: Throwable?) : DownloadError() {
        override val message = "Network error: ${cause?.message ?: "Unknown network issue"}"
    }

    data class Timeout(val timeoutSeconds: Int) : DownloadError() {
        override val message = "Download timed out after $timeoutSeconds seconds"
    }

    object ConnectionLost : DownloadError() {
        override val message = "Network connection lost during download"
    }

    // HTTP-specific errors
    data class HttpError(val statusCode: Int, val statusMessage: String? = null) : DownloadError() {
        override val message = "HTTP error $statusCode${statusMessage?.let { ": $it" } ?: ""}"
    }

    // File and storage errors
    data class InsufficientSpace(val required: Long, val available: Long) : DownloadError() {
        override val message = "Insufficient storage space. Required: ${required / 1024 / 1024}MB, Available: ${available / 1024 / 1024}MB"
    }

    data class PartialDownload(val expected: Long, val actual: Long) : DownloadError() {
        override val message = "Partial download: expected $expected bytes, got $actual bytes"
    }

    data class ChecksumMismatch(val expected: String, val actual: String) : DownloadError() {
        override val message = "Checksum mismatch: expected $expected, got $actual"
    }

    // Archive and extraction errors
    data class ExtractionFailed(val reason: String) : DownloadError() {
        override val message = "Failed to extract archive: $reason"
    }

    data class UnsupportedArchive(val format: String) : DownloadError() {
        override val message = "Unsupported archive format: $format"
    }

    // Model-specific errors
    data class ModelNotFound(val modelId: String) : DownloadError() {
        override val message = "Model not found: $modelId"
    }

    // Operation control errors
    object Cancelled : DownloadError() {
        override val message = "Download was cancelled"
    }

    // Generic errors
    data class UnknownError(override val message: String, override val cause: Throwable? = null) : DownloadError()
}
