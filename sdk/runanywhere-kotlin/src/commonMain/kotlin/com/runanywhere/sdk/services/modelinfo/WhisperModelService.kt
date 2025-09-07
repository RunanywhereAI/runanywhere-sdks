package com.runanywhere.sdk.services.modelinfo

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.network.APIClient
import com.runanywhere.sdk.network.MockNetworkService
import com.runanywhere.sdk.network.postJson
import com.runanywhere.sdk.network.getJson
import com.runanywhere.sdk.services.download.DownloadService
import com.runanywhere.sdk.services.download.DownloadProgress
import com.runanywhere.sdk.services.download.FileManager
import com.runanywhere.sdk.utils.SimpleInstant
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable

/**
 * Whisper-specific model service for fetching and managing Whisper models
 * Matches iOS model download and management patterns exactly
 */
class WhisperModelService(
    private val apiClient: APIClient,
    private val modelInfoService: ModelInfoService,
    private val downloadService: DownloadService? = null,
    private val fileManager: FileManager? = null,
    private val useMockService: Boolean = SDKConstants.Development.ENABLE_MOCK_SERVICES
) {
    private val logger = SDKLogger("WhisperModelService")

    // Predefined Whisper models matching iOS implementation
    private val defaultWhisperModels = listOf(
        WhisperModelSpec(
            id = "whisper-tiny",
            name = "Whisper Tiny",
            size = 39_000_000L, // 39 MB
            memoryRequired = 100_000_000L, // 100 MB
            description = "Smallest and fastest model, suitable for real-time transcription"
        ),
        WhisperModelSpec(
            id = "whisper-base",
            name = "Whisper Base",
            size = 74_000_000L, // 74 MB
            memoryRequired = 200_000_000L, // 200 MB
            description = "Good balance between speed and accuracy"
        ),
        WhisperModelSpec(
            id = "whisper-small",
            name = "Whisper Small",
            size = 244_000_000L, // 244 MB
            memoryRequired = 500_000_000L, // 500 MB
            description = "Better accuracy with reasonable performance"
        ),
        WhisperModelSpec(
            id = "whisper-medium",
            name = "Whisper Medium",
            size = 769_000_000L, // 769 MB
            memoryRequired = 1_500_000_000L, // 1.5 GB
            description = "High accuracy for professional use"
        ),
        WhisperModelSpec(
            id = "whisper-large",
            name = "Whisper Large",
            size = 1_550_000_000L, // 1.55 GB
            memoryRequired = 3_000_000_000L, // 3 GB
            description = "Best accuracy, requires significant resources"
        )
    )

    /**
     * Fetch available Whisper models from backend or use defaults
     * In development mode, uses MockNetworkService
     */
    suspend fun fetchWhisperModels(): List<ModelInfo> {
        logger.info("Fetching Whisper models (mock=$useMockService)")

        // Use mock service in development mode
        if (useMockService) {
            val mockService = MockNetworkService()
            val mockModels = if (SDKConstants.Development.USE_COMPREHENSIVE_MOCKS) {
                mockService.createComprehensiveMockModels()
            } else {
                mockService.fetchModels()
            }

            // Filter for Whisper models only
            val whisperModels = mockModels.filter { model ->
                model.category == ModelCategory.SPEECH_RECOGNITION &&
                (model.preferredFramework == LLMFramework.WHISPER_CPP ||
                 model.preferredFramework == LLMFramework.WHISPER_KIT)
            }

            // Save to local cache
            whisperModels.forEach { model ->
                try {
                    modelInfoService.saveModel(model)
                } catch (e: Exception) {
                    logger.error("Failed to save mock model ${model.id}: ${e.message}")
                }
            }

            logger.info("Fetched ${whisperModels.size} Whisper models from mock service")
            return whisperModels
        }

        // Production mode - try remote first
        try {
            val remoteModels = fetchRemoteWhisperModels()
            if (remoteModels.isNotEmpty()) {
                // Save to local cache
                remoteModels.forEach { model ->
                    modelInfoService.saveModel(model)
                }
                logger.info("Fetched ${remoteModels.size} Whisper models from backend")
                return remoteModels
            }
        } catch (e: Exception) {
            logger.warn("Failed to fetch remote models, using defaults: ${e.message}")
        }

        // Fallback to default models
        val defaultModels = defaultWhisperModels.map { spec ->
            ModelInfo(
                id = spec.id,
                name = spec.name,
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = getWhisperModelUrl(spec.id),
                downloadSize = spec.size,
                memoryRequired = spec.memoryRequired,
                preferredFramework = LLMFramework.WHISPER_CPP,
                localPath = null,
                createdAt = SimpleInstant.now(),
                updatedAt = SimpleInstant.now()
            )
        }

        // Save default models to cache
        defaultModels.forEach { model ->
            try {
                modelInfoService.saveModel(model)
            } catch (e: Exception) {
                logger.error("Failed to save default model ${model.id}: ${e.message}")
            }
        }

        logger.info("Using ${defaultModels.size} default Whisper models")
        return defaultModels
    }

    /**
     * Fetch Whisper models from remote backend
     */
    private suspend fun fetchRemoteWhisperModels(): List<ModelInfo> {
        return try {
            val response = apiClient.getJson<WhisperModelsResponse>(
                endpoint = "v1/models/whisper",
                requiresAuth = true
            )

            response.models.map { remoteModel ->
                ModelInfo(
                    id = remoteModel.id,
                    name = remoteModel.name,
                    category = ModelCategory.SPEECH_RECOGNITION,
                    format = ModelFormat.GGML,
                    downloadURL = remoteModel.downloadUrl,
                    downloadSize = remoteModel.size,
                    memoryRequired = remoteModel.memoryRequired,
                    preferredFramework = LLMFramework.WHISPER_CPP,
                    localPath = null,
                    createdAt = SimpleInstant.now(),
                    updatedAt = SimpleInstant.now()
                )
            }
        } catch (e: Exception) {
            logger.error("Failed to fetch remote Whisper models: ${e.message}")
            emptyList()
        }
    }

    /**
     * Get the download URL for a Whisper model
     * Uses Hugging Face as the default source
     */
    private fun getWhisperModelUrl(modelId: String): String {
        // Map to ggerganov's whisper.cpp models on Hugging Face
        val modelFile = when (modelId) {
            "whisper-tiny" -> "ggml-tiny.bin"
            "whisper-base" -> "ggml-base.bin"
            "whisper-small" -> "ggml-small.bin"
            "whisper-medium" -> "ggml-medium.bin"
            "whisper-large" -> "ggml-large-v3.bin"
            else -> "ggml-base.bin"
        }

        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelFile"
    }

    /**
     * Download a Whisper model with progress tracking
     * Matches iOS download pattern exactly
     */
    suspend fun downloadModel(
        modelId: String,
        progressHandler: ((DownloadProgress) -> Unit)? = null
    ): String {
        logger.info("Starting download for Whisper model: $modelId")

        // Get model info
        val model = modelInfoService.getModel(modelId)
            ?: throw SDKError.ModelNotFound(modelId)

        // Check if already downloaded
        if (!model.localPath.isNullOrEmpty() && fileManager?.fileExists(model.localPath!!) == true) {
            logger.info("Model $modelId already downloaded at: ${model.localPath}")
            return model.localPath!!
        }

        // Use download service if available
        val downloadService = this.downloadService
            ?: throw SDKError.ServiceNotAvailable("Download service not available")

        // Download the model
        val localPath = downloadService.downloadModel(model, progressHandler)

        // Update model with local path
        markModelAsDownloaded(modelId, localPath)

        return localPath
    }

    /**
     * Stream download progress for a model
     */
    suspend fun downloadModelStream(modelId: String): Flow<DownloadProgress>? {
        val model = modelInfoService.getModel(modelId) ?: return null
        return downloadService?.downloadModelStream(model)
    }

    /**
     * Check if a Whisper model is downloaded locally
     */
    suspend fun isModelDownloaded(modelId: String): Boolean {
        val model = modelInfoService.getModel(modelId)
        return if (model?.localPath != null && fileManager != null) {
            fileManager.fileExists(model.localPath!!)
        } else {
            false
        }
    }

    /**
     * Get the local path for a downloaded Whisper model
     */
    suspend fun getModelPath(modelId: String): String? {
        val model = modelInfoService.getModel(modelId) ?: return null

        // Verify file exists
        return if (model.localPath != null && fileManager?.fileExists(model.localPath!!) == true) {
            model.localPath
        } else {
            null
        }
    }

    /**
     * Update download status after model is downloaded
     */
    suspend fun markModelAsDownloaded(modelId: String, localPath: String) {
        val model = modelInfoService.getModel(modelId)
            ?: throw SDKError.ModelNotFound(modelId)

        val updatedModel = model.copy(
            localPath = localPath,
            updatedAt = SimpleInstant.now()
        )

        modelInfoService.saveModel(updatedModel)
        logger.info("Model $modelId marked as downloaded at: $localPath")
    }

    /**
     * Delete a downloaded model
     */
    suspend fun deleteModel(modelId: String): Boolean {
        val model = modelInfoService.getModel(modelId) ?: return false

        // Delete files if they exist
        if (model.localPath != null && fileManager != null) {
            val deleted = fileManager.deleteFile(model.localPath!!)
            if (deleted) {
                // Update model to remove local path
                val updatedModel = model.copy(
                    localPath = null,
                    updatedAt = SimpleInstant.now()
                )
                modelInfoService.saveModel(updatedModel)
                logger.info("Deleted model $modelId from: ${model.localPath}")
                return true
            }
        }

        return false
    }

    /**
     * Get storage size for a model
     */
    suspend fun getModelSize(modelId: String): Long {
        val model = modelInfoService.getModel(modelId) ?: return 0L

        if (model.localPath != null && fileManager != null) {
            return fileManager.getDirectorySize(model.localPath!!)
        }

        return model.downloadSize ?: 0L
    }
}

/**
 * Whisper model specification
 */
private data class WhisperModelSpec(
    val id: String,
    val name: String,
    val size: Long,
    val memoryRequired: Long,
    val description: String
)

/**
 * API response for Whisper models
 */
@Serializable
private data class WhisperModelsResponse(
    val models: List<RemoteWhisperModel>
)

@Serializable
private data class RemoteWhisperModel(
    val id: String,
    val name: String,
    val description: String,
    val downloadUrl: String,
    val size: Long,
    val memoryRequired: Long,
    val version: String,
    val language: String? = null
)
