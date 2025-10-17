package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.models.download.DownloadProgress
import com.runanywhere.sdk.models.download.DownloadState
import com.runanywhere.sdk.public.RunAnywhereSDK
import io.ktor.client.*
import io.ktor.client.plugins.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.utils.io.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import okio.FileSystem
import okio.Path.Companion.toPath
import okio.buffer

/**
 * Download extension for RunAnywhere SDK
 * Matches iOS RunAnywhere+Download.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Download.swift
 *
 * Provides download with real-time progress tracking matching iOS:
 * - downloadModelWithProgress() - Download model with progress updates
 */

private val downloadLogger: SDKLogger by lazy { SDKLogger.shared }
private val downloadFileManager: SimplifiedFileManager by lazy { SimplifiedFileManager.shared }

/**
 * Download model with progress tracking
 * Matches iOS static func downloadModelWithProgress(_ modelId: String) -> AsyncStream<DownloadProgress>
 *
 * @param modelId The model identifier to download
 * @return Flow emitting download progress updates
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Suppress("DEPRECATION")
fun RunAnywhereSDK.downloadModelWithProgress(modelId: String): Flow<DownloadProgress> = flow {
    downloadLogger.debug("Starting download for model: $modelId")

    val startTime = kotlinx.datetime.Instant.fromEpochMilliseconds(System.currentTimeMillis())

    try {
        // Get model info to find download URL
        val models = availableModels()
        val model = models.find { it.id == modelId }
            ?: throw IllegalArgumentException("Model not found: $modelId")

        val downloadURL = model.downloadURL
            ?: throw IllegalStateException("Model has no download URL: $modelId")

        downloadLogger.info("Downloading model from: $downloadURL")

        // Create HTTP client with timeout configuration
        val httpClient = HttpClient {
            install(HttpTimeout) {
                requestTimeoutMillis = 300000 // 5 minutes
                connectTimeoutMillis = 60000  // 1 minute
                socketTimeoutMillis = 60000   // 1 minute
            }
        }

        // Determine output path
        val fileSystem = FileSystem.SYSTEM
        val fileName = "${modelId}.${model.format.value}"
        val outputPath = (downloadFileManager.modelsDirectory / fileName).toString().toPath()

        // Ensure models directory exists
        downloadFileManager.createDirectory(downloadFileManager.modelsDirectory.toString())

        var bytesDownloaded = 0L
        var lastEmitTime = System.currentTimeMillis()
        var lastEmitBytes = 0L

        httpClient.prepareGet(downloadURL).execute { response ->
            val totalBytes = response.headers["Content-Length"]?.toLongOrNull() ?: 0L
            downloadLogger.debug("Download size: $totalBytes bytes")

            // Emit initial progress
            emit(
                DownloadProgress(
                    modelId = modelId,
                    bytesDownloaded = 0L,
                    totalBytes = totalBytes,
                    percentage = 0.0,
                    speed = 0L,
                    estimatedTimeRemaining = null,
                    state = DownloadState.DOWNLOADING,
                    startTime = startTime,
                    error = null
                )
            )

            val channel = response.bodyAsChannel()

            fileSystem.sink(outputPath).buffer().use { sink ->
                val buffer = ByteArray(8192)

                while (!channel.isClosedForRead) {
                    val bytesRead = channel.readAvailable(buffer)
                    if (bytesRead == -1) break

                    sink.write(buffer, 0, bytesRead)
                    bytesDownloaded += bytesRead

                    // Emit progress every 100ms or on completion
                    val now = System.currentTimeMillis()
                    val timeSinceLastEmit = now - lastEmitTime

                    if (timeSinceLastEmit >= 100 || bytesDownloaded == totalBytes) {
                        // Calculate speed (bytes per second)
                        val bytesSinceLastEmit = bytesDownloaded - lastEmitBytes
                        val speed = if (timeSinceLastEmit > 0) {
                            (bytesSinceLastEmit * 1000.0 / timeSinceLastEmit).toLong()
                        } else {
                            0L
                        }

                        // Calculate percentage
                        val percentage = if (totalBytes > 0) {
                            (bytesDownloaded.toDouble() / totalBytes.toDouble()) * 100.0
                        } else {
                            0.0
                        }

                        // Calculate ETA
                        val remainingBytes = totalBytes - bytesDownloaded
                        val estimatedTimeRemaining = if (speed > 0) {
                            remainingBytes / speed
                        } else {
                            null
                        }

                        emit(
                            DownloadProgress(
                                modelId = modelId,
                                bytesDownloaded = bytesDownloaded,
                                totalBytes = totalBytes,
                                percentage = percentage,
                                speed = speed,
                                estimatedTimeRemaining = estimatedTimeRemaining,
                                state = DownloadState.DOWNLOADING,
                                startTime = startTime,
                                error = null
                            )
                        )

                        lastEmitTime = now
                        lastEmitBytes = bytesDownloaded
                    }
                }
            }
        }

        httpClient.close()

        // Emit completion
        emit(
            DownloadProgress(
                modelId = modelId,
                bytesDownloaded = bytesDownloaded,
                totalBytes = bytesDownloaded,
                percentage = 100.0,
                speed = 0L,
                estimatedTimeRemaining = 0L,
                state = DownloadState.COMPLETED,
                startTime = startTime,
                error = null
            )
        )

        downloadLogger.info("Download completed for model: $modelId")

    } catch (e: Exception) {
        downloadLogger.error("Download failed for model: $modelId", e)

        // Emit failure
        emit(
            DownloadProgress(
                modelId = modelId,
                bytesDownloaded = 0L,
                totalBytes = 0L,
                percentage = 0.0,
                speed = 0L,
                estimatedTimeRemaining = null,
                state = DownloadState.FAILED,
                startTime = startTime,
                error = e.message
            )
        )

        throw e
    }
}
