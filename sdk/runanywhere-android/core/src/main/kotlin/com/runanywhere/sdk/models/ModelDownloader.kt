package com.runanywhere.sdk.models

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.net.HttpURLConnection

/**
 * Model downloader for downloading models from remote sources
 */
class ModelDownloader {

    /**
     * Download a model with progress tracking
     */
    suspend fun downloadModel(
        modelId: String,
        onProgress: suspend (Float) -> Unit
    ): String = withContext(Dispatchers.IO) {
        val url = getModelUrl(modelId)
        val destination = ModelStorage.getModelDestination(modelId)

        // Download with progress tracking
        downloadFile(url, destination, onProgress)

        return@withContext destination.absolutePath
    }

    /**
     * Get the download URL for a model
     */
    private fun getModelUrl(modelId: String): String {
        return when (modelId) {
            "whisper-tiny" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            "whisper-base" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            "whisper-small" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            "whisper-medium" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
            else -> throw IllegalArgumentException("Unknown model: $modelId")
        }
    }

    /**
     * Download a file with progress tracking
     */
    private suspend fun downloadFile(
        url: String,
        destination: File,
        onProgress: suspend (Float) -> Unit
    ) {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10000
        connection.readTimeout = 30000

        try {
            connection.connect()
            val totalSize = connection.contentLength.toLong()

            connection.inputStream.use { input ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalBytesRead = 0L

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead

                        if (totalSize > 0) {
                            val progress = totalBytesRead.toFloat() / totalSize
                            onProgress(progress)
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }
}
