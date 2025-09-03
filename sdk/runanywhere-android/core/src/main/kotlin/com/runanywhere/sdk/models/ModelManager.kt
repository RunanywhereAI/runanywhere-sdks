package com.runanywhere.sdk.models

import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.ModelEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Model information
 */
data class ModelInfo(
    val id: String,
    val size: String,
    val description: String,
    val url: String? = null
)

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
            return it.absolutePath
        }

        // Download if needed
        return downloader.downloadModel(modelId) { progress ->
            EventBus.emit(ModelEvent.DownloadProgress(modelId, progress))
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
                "whisper-tiny",
                "39MB",
                "Fastest, lower accuracy",
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            ),
            ModelInfo(
                "whisper-base",
                "74MB",
                "Good balance",
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            ),
            ModelInfo(
                "whisper-small",
                "244MB",
                "Better accuracy",
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            ),
            ModelInfo(
                "whisper-medium",
                "769MB",
                "High accuracy",
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
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
