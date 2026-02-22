/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementation for LoRA adapter downloading.
 * Uses plain HttpURLConnection (same pattern as AndroidSimpleDownloader).
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

private val loraDownloadLogger = SDKLogger("LoRADownload")

actual fun RunAnywhere.downloadLoraAdapter(url: String, filename: String): Flow<LoraDownloadProgress> =
    callbackFlow {
        trySend(
            LoraDownloadProgress(
                progress = 0f,
                bytesDownloaded = 0,
                totalBytes = null,
                state = LoraDownloadState.PENDING,
            ),
        )

        try {
            val destDir = File(CppBridgeModelPaths.getModelsDirectory(), "lora")

            val localPath = withContext(Dispatchers.IO) {
                destDir.mkdirs()

                val destFile = File(destDir, filename)
                val tempFile = File(destDir, "$filename.tmp")

                loraDownloadLogger.info("Downloading LoRA: $url -> ${destFile.absolutePath}")

                val connection = URL(url).openConnection() as HttpURLConnection
                connection.connectTimeout = 30_000
                connection.readTimeout = 60_000
                connection.setRequestProperty("User-Agent", "RunAnywhere-SDK/Kotlin")

                try {
                    connection.connect()

                    val responseCode = connection.responseCode
                    if (responseCode != HttpURLConnection.HTTP_OK) {
                        throw Exception("HTTP error: $responseCode")
                    }

                    val totalBytes = connection.contentLengthLong

                    trySend(
                        LoraDownloadProgress(
                            progress = 0f,
                            bytesDownloaded = 0,
                            totalBytes = if (totalBytes > 0) totalBytes else null,
                            state = LoraDownloadState.DOWNLOADING,
                        ),
                    )

                    connection.inputStream.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            val buffer = ByteArray(8192)
                            var bytesDownloaded = 0L
                            var lastProgressTime = System.currentTimeMillis()
                            var bytesRead: Int

                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                output.write(buffer, 0, bytesRead)
                                bytesDownloaded += bytesRead

                                val now = System.currentTimeMillis()
                                if (now - lastProgressTime >= 150) {
                                    lastProgressTime = now
                                    val progress = if (totalBytes > 0) {
                                        bytesDownloaded.toFloat() / totalBytes
                                    } else {
                                        0f
                                    }

                                    trySend(
                                        LoraDownloadProgress(
                                            progress = progress,
                                            bytesDownloaded = bytesDownloaded,
                                            totalBytes = if (totalBytes > 0) totalBytes else null,
                                            state = LoraDownloadState.DOWNLOADING,
                                        ),
                                    )
                                }
                            }
                        }
                    }

                    // Move temp to final
                    if (destFile.exists()) destFile.delete()
                    if (!tempFile.renameTo(destFile)) {
                        tempFile.copyTo(destFile, overwrite = true)
                        tempFile.delete()
                    }

                    loraDownloadLogger.info("LoRA downloaded: ${destFile.absolutePath} (${destFile.length()} bytes)")
                    destFile.absolutePath
                } finally {
                    connection.disconnect()
                }
            }

            trySend(
                LoraDownloadProgress(
                    progress = 1f,
                    bytesDownloaded = File(localPath).length(),
                    totalBytes = File(localPath).length(),
                    state = LoraDownloadState.COMPLETED,
                    localPath = localPath,
                ),
            )

            close()
        } catch (e: Exception) {
            loraDownloadLogger.error("LoRA download failed: ${e.message}")
            trySend(
                LoraDownloadProgress(
                    progress = 0f,
                    bytesDownloaded = 0,
                    totalBytes = null,
                    state = LoraDownloadState.ERROR,
                    error = e.message ?: "Download failed",
                ),
            )
            close(e)
        }

        awaitClose {
            loraDownloadLogger.debug("LoRA download flow closed")
        }
    }
