package com.runanywhere.sdk.services

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Common download service interface
 * Platform-specific implementations handle actual downloading
 */
expect class DownloadService() {
    suspend fun downloadModel(
        model: ModelInfo,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): String
}
