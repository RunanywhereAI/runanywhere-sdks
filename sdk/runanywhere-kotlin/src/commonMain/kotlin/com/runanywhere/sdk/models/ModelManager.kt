package com.runanywhere.sdk.models

import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.runanywhere.sdk.storage.FileSystem
import com.runanywhere.sdk.services.download.DownloadService

/**
 * Model handle for loaded models
 */
data class ModelHandle(
    val modelId: String,
    val modelPath: String
)

/**
 * Model Manager for handling model downloads and storage
 */
class ModelManager(
    private val fileSystem: FileSystem,
    private val downloadService: DownloadService
) {
    private val storage = ModelStorage()
    private val downloader = ModelDownloader(fileSystem, downloadService)
    private val loadedModels = mutableMapOf<String, ModelInfo>()

    /**
     * Ensure model is available locally, download if needed
     */
    suspend fun ensureModel(modelInfo: ModelInfo): String {
        // Check if model exists locally
        storage.getModelPath(modelInfo.id)?.let {
            return it
        }

        // Download if needed
        return downloader.downloadModel(modelInfo) { progress ->
            // TODO: Publish progress events when EventBus supports non-suspend callbacks
            // or refactor to use Flow-based progress
        }
    }

    /**
     * Load a model and return its handle
     */
    suspend fun loadModel(modelInfo: ModelInfo): ModelHandle {
        val path = ensureModel(modelInfo)
        return ModelHandle(modelInfo.id, path)
    }

    /**
     * Get list of available models - only Whisper Base as default
     */
    fun getAvailableModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = SDKConstants.ModelUrls.WHISPER_BASE.takeIf { it.isNotEmpty() },
                downloadSize = 141L * 1024 * 1024 // 141MB - GGML format
            )
        )
    }

    /**
     * Check if a model is available locally
     */
    fun isModelAvailable(modelId: String): Boolean {
        return storage.getModelPath(modelId) != null
    }

    /**
     * Delete a model from local storage
     */
    suspend fun deleteModel(modelId: String) {
        withContext(Dispatchers.Default) {
            storage.deleteModel(modelId)
            loadedModels.remove(modelId)
        }
    }
}
