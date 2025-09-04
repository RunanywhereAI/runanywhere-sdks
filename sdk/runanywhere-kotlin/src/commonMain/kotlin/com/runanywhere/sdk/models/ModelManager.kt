package com.runanywhere.sdk.models

import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

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
class ModelManager {
    private val storage = ModelStorage()
    private val downloader = ModelDownloader()
    private val loadedModels = mutableMapOf<String, ModelInfo>()

    /**
     * Ensure model is available locally, download if needed
     */
    suspend fun ensureModel(modelId: String): String {
        // Check if model exists locally
        storage.getModelPath(modelId)?.let {
            return it
        }

        // Download if needed
        return downloader.downloadModel(modelId) { progress ->
            kotlinx.coroutines.runBlocking {
                EventBus.publish(SDKModelEvent.DownloadProgress(modelId, progress))
            }
        }
    }

    /**
     * Load a model and return its handle
     */
    suspend fun loadModel(modelId: String): ModelHandle {
        val path = ensureModel(modelId)
        return ModelHandle(modelId, path)
    }

    /**
     * Get list of available models
     */
    fun getAvailableModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                downloadSize = 39L * 1024 * 1024 // 39MB
            ),
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                downloadSize = 74L * 1024 * 1024 // 74MB
            ),
            ModelInfo(
                id = "whisper-small",
                name = "Whisper Small",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
                downloadSize = 244L * 1024 * 1024 // 244MB
            ),
            ModelInfo(
                id = "whisper-medium",
                name = "Whisper Medium",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
                downloadSize = 769L * 1024 * 1024 // 769MB
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
        withContext(Dispatchers.IO) {
            storage.deleteModel(modelId)
            loadedModels.remove(modelId)
        }
    }
}
