package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * DEAD SIMPLE Android downloader - NO Ktor, NO buffering, just plain HttpURLConnection
 * This is a temporary solution to avoid Ktor's memory buffering issues
 */
object AndroidSimpleDownloader {
    private val logger = SDKLogger.download

    /**
     * Download a file from URL to destination path
     * Returns the number of bytes downloaded
     */
    suspend fun download(
        url: String,
        destinationPath: String,
        progressCallback: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)? = null,
    ): Long =
        withContext(Dispatchers.IO) {
            logger.info("Starting simple download - url: $url, destination: $destinationPath")

            val urlConnection = URL(url).openConnection() as HttpURLConnection
            urlConnection.requestMethod = "GET"
            urlConnection.connectTimeout = 30000 // 30 seconds
            urlConnection.readTimeout = 30000 // 30 seconds

            try {
                urlConnection.connect()

                val responseCode = urlConnection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw Exception("HTTP error: $responseCode")
                }

                val totalBytes = urlConnection.contentLengthLong
                logger.info("Download started - totalBytes: $totalBytes")

                // Create temp file
                val tempPath = "$destinationPath.tmp"

                FileOutputStream(tempPath).use { output ->
                    urlConnection.inputStream.use { input ->
                        val buffer = ByteArray(8192) // 8KB buffer
                        var bytesDownloaded = 0L
                        var bytesRead: Int
                        var lastReportTime = System.currentTimeMillis()

                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            bytesDownloaded += bytesRead

                            // Report progress every 100ms
                            val currentTime = System.currentTimeMillis()
                            if (currentTime - lastReportTime >= 100) {
                                progressCallback?.invoke(bytesDownloaded, totalBytes)
                                lastReportTime = currentTime

                                // Log every 10%
                                if (totalBytes > 0) {
                                    val percent = (bytesDownloaded.toDouble() / totalBytes * 100).toInt()
                                    if (percent % 10 == 0) {
                                        logger.debug("Download progress: $percent% ($bytesDownloaded / $totalBytes bytes)")
                                    }
                                }
                            }
                        }

                        logger.info("Download completed - bytesDownloaded: $bytesDownloaded")
                    }
                }

                // Move temp to final destination
                val tempFile = java.io.File(tempPath)
                val destFile = java.io.File(destinationPath)
                destFile.parentFile?.mkdirs()
                tempFile.renameTo(destFile)

                val finalSize = destFile.length()
                logger.info("File moved to destination - size: $finalSize")

                finalSize
            } finally {
                urlConnection.disconnect()
            }
        }
}
