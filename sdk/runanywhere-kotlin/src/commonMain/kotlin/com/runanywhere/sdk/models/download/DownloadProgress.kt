package com.runanywhere.sdk.models.download

import kotlinx.datetime.Instant
import kotlinx.serialization.Contextual
import kotlinx.serialization.Serializable

/**
 * Download progress information
 * Matches iOS DownloadProgress struct from RunAnywhere+Download.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Download/DownloadProgress.swift
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class DownloadProgress(
    val modelId: String,
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val percentage: Double,            // 0.0 to 100.0
    val speed: Long,                   // bytes per second
    val estimatedTimeRemaining: Long?,  // seconds, null if unknown
    val state: DownloadState,
    @Contextual val startTime: Instant,
    val error: String? = null
) {
    /**
     * Formatted download speed (e.g., "1.5 MB/s")
     * Matches iOS formattedSpeed computed property
     */
    fun formattedSpeed(): String {
        return when {
            speed >= 1_000_000_000 -> String.format("%.2f GB/s", speed / 1_000_000_000.0)
            speed >= 1_000_000 -> String.format("%.2f MB/s", speed / 1_000_000.0)
            speed >= 1_000 -> String.format("%.2f KB/s", speed / 1_000.0)
            else -> "$speed B/s"
        }
    }

    /**
     * Formatted time remaining (e.g., "2m 30s")
     * Matches iOS formattedTimeRemaining computed property
     */
    fun formattedTimeRemaining(): String {
        val seconds = estimatedTimeRemaining ?: return "Unknown"
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val secs = seconds % 60

        return when {
            hours > 0 -> String.format("%dh %dm", hours, minutes)
            minutes > 0 -> String.format("%dm %ds", minutes, secs)
            else -> String.format("%ds", secs)
        }
    }

    /**
     * Formatted download size (e.g., "1.5 MB / 2.0 GB")
     * Matches iOS formattedSize computed property
     */
    fun formattedSize(): String {
        return "${formatBytes(bytesDownloaded)} / ${formatBytes(totalBytes)}"
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1_000_000_000 -> String.format("%.2f GB", bytes / 1_000_000_000.0)
            bytes >= 1_000_000 -> String.format("%.2f MB", bytes / 1_000_000.0)
            bytes >= 1_000 -> String.format("%.2f KB", bytes / 1_000.0)
            else -> "$bytes B"
        }
    }
}

/**
 * Download state
 * Matches iOS DownloadState enum
 */
@Serializable
enum class DownloadState {
    PENDING,        // Waiting to start
    DOWNLOADING,    // Currently downloading
    PAUSED,         // Paused by user
    COMPLETED,      // Download finished successfully
    FAILED,         // Download failed
    CANCELLED       // Download cancelled by user
}

/**
 * Download task information
 * Matches iOS DownloadTask struct
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class DownloadTask(
    val id: String,
    val modelId: String,
    val url: String,
    val destinationPath: String,
    val state: DownloadState,
    val progress: DownloadProgress?,
    @Contextual val createdAt: Instant,
    @Contextual val updatedAt: Instant
)
