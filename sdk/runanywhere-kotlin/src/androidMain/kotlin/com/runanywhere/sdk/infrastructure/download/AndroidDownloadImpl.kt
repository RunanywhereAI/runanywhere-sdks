package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.channels.Channel

/**
 * Android implementation uses AndroidSimpleDownloader
 * This bypasses Ktor entirely to avoid OutOfMemoryError
 */
internal actual suspend fun downloadWithPlatformImplementation(
    downloadURL: String,
    destinationPath: String,
    modelId: String,
    expectedSize: Long,
    progressChannel: Channel<DownloadProgress>,
) {
    val logger = SDKLogger("AndroidDownloadImpl")

    logger.info("Using AndroidSimpleDownloader for model: $modelId")

    var lastProgressTime = System.currentTimeMillis()
    var lastBytesDownloaded = 0L
    var lastLoggedPercent = 0

    // Use the simple downloader with progress callbacks
    val finalSize =
        AndroidSimpleDownloader.download(
            url = downloadURL,
            destinationPath = destinationPath,
            progressCallback = { bytesDownloaded, totalBytes ->
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastProgressTime >= 100) {
                    val elapsedTime = (currentTime - lastProgressTime) / 1000.0
                    val bytesInInterval = bytesDownloaded - lastBytesDownloaded
                    val speed = if (elapsedTime > 0) bytesInInterval / elapsedTime else null
                    val remainingBytes = totalBytes - bytesDownloaded
                    val eta = if (speed != null && speed > 0) remainingBytes / speed else null

                    progressChannel.trySend(
                        DownloadProgress(
                            bytesDownloaded = bytesDownloaded,
                            totalBytes = totalBytes,
                            state = DownloadState.Downloading,
                            estimatedTimeRemaining = eta,
                            speed = speed,
                        ),
                    )

                    // Log at 10% intervals
                    val progressPercent = if (totalBytes > 0) (bytesDownloaded.toDouble() / totalBytes) * 100 else 0.0
                    val currentPercent = progressPercent.toInt()
                    if (currentPercent >= lastLoggedPercent + 10) {
                        logger.debug(
                            "Download progress - modelId: $modelId, progress: $progressPercent%, bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes",
                        )
                        lastLoggedPercent = currentPercent
                    }
                    lastProgressTime = currentTime
                    lastBytesDownloaded = bytesDownloaded
                }
            },
        )

    // Final progress update
    progressChannel.trySend(
        DownloadProgress(
            bytesDownloaded = finalSize,
            totalBytes = finalSize,
            state = DownloadState.Completed,
        ),
    )

    logger.info(
        "Download completed - modelId: $modelId, localPath: $destinationPath, fileSize: $finalSize",
    )
}
