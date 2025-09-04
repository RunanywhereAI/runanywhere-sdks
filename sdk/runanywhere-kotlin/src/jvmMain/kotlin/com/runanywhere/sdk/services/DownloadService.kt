package com.runanywhere.sdk.services

import com.runanywhere.sdk.models.ModelInfo

/**
 * JVM implementation of DownloadService using JvmDownloadService
 */
actual class DownloadService {
    private val jvmDownloadService = JvmDownloadService()

    actual suspend fun downloadModel(
        model: ModelInfo,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): String {
        return jvmDownloadService.downloadModel(model, destinationPath, onProgress)
    }
}
