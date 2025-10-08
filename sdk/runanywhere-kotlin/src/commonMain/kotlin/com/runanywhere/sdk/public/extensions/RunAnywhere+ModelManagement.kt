package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.LoadedModelWithService
import kotlin.random.Random
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Model Management Extensions for RunAnywhere SDK - EXACT copy of iOS implementation
 * This provides the public API for model management operations
 */

private val logger = SDKLogger("ModelManagement")

/**
 * Load a model by identifier and return model info
 * @param modelIdentifier The model to load
 * @return Information about the loaded model
 */
suspend fun loadModelWithInfo(modelIdentifier: String): ModelInfo = withContext(Dispatchers.IO) {
    EventBus.publish(SDKModelEvent.LoadStarted(modelIdentifier))

    try {
        // Use existing service logic directly
        val loadedModel = ServiceContainer.shared.modelLoadingService.loadModel(modelIdentifier)

        // IMPORTANT: Set the loaded model in the generation service
        ServiceContainer.shared.generationService.setCurrentModel(loadedModel)

        EventBus.publish(SDKModelEvent.LoadCompleted(modelIdentifier))
        return@withContext loadedModel.model
    } catch (error: Throwable) {
        EventBus.publish(SDKModelEvent.LoadFailed(modelIdentifier, error))
        throw error
    }
}

/**
 * Unload the currently loaded model
 */
suspend fun unloadModel() = withContext(Dispatchers.IO) {
    EventBus.publish(SDKModelEvent.UnloadStarted)

    try {
        // Get the current model ID from generation service
        val currentModel = ServiceContainer.shared.generationService.getCurrentModel()
        if (currentModel != null) {
            val modelId = currentModel.model.id

            // Unload through model loading service
            ServiceContainer.shared.modelLoadingService.unloadModel(modelId)

            // Clear from generation service
            ServiceContainer.shared.generationService.setCurrentModel(null)
        }

        EventBus.publish(SDKModelEvent.UnloadCompleted)
    } catch (error: Throwable) {
        EventBus.publish(SDKModelEvent.UnloadFailed(error))
        throw error
    }
}

/**
 * List all available models
 * @return Array of available models
 */
suspend fun listAvailableModels(): List<ModelInfo> = withContext(Dispatchers.IO) {
    EventBus.publish(SDKModelEvent.ListRequested)

    // Use model registry to discover models
    val models = ServiceContainer.shared.modelRegistry.discoverModels()
    EventBus.publish(SDKModelEvent.ListCompleted(models))
    return@withContext models
}

/**
 * Download a model
 * @param modelIdentifier The model to download
 */
suspend fun downloadModel(modelIdentifier: String) = withContext(Dispatchers.IO) {
    EventBus.publish(SDKModelEvent.DownloadStarted(modelIdentifier))

    try {
        // Get the model info first
        val modelService = ServiceContainer.shared.modelInfoService

        // Log available models for debugging
        val allModels = modelService.loadStoredModels()
        logger.debug("Available models in database: ${allModels.map { it.id }}")
        logger.debug("Looking for model: $modelIdentifier")

        var modelInfo = modelService.getModel(modelIdentifier)
        if (modelInfo == null) {
            logger.error("Model not found in database: $modelIdentifier")
            // Try to find in registry as fallback
            val registryModel = ServiceContainer.shared.modelRegistry.getModel(modelIdentifier)
            if (registryModel != null) {
                logger.debug("Found model in registry, saving to database")
                modelService.saveModel(registryModel)
                // Now try again
                modelInfo = modelService.getModel(modelIdentifier)
                    ?: throw SDKError.ModelNotFound(modelIdentifier)
            } else {
                throw SDKError.ModelNotFound(modelIdentifier)
            }
        }

        // Use the download service through model manager
        val downloadedPath = ServiceContainer.shared.modelManager.ensureModel(modelInfo)

        // Update model info with local path after successful download
        modelService.updateDownloadStatus(modelIdentifier, isDownloaded = true, localPath = downloadedPath)

        // Also update the model in the registry with the new local path
        val updatedModel = modelService.getModel(modelIdentifier)
        if (updatedModel != null) {
            ServiceContainer.shared.modelRegistry.updateModel(updatedModel)
        }

        EventBus.publish(SDKModelEvent.DownloadCompleted(modelIdentifier))
    } catch (error: Throwable) {
        EventBus.publish(SDKModelEvent.DownloadFailed(modelIdentifier, error))
        throw error
    }
}

/**
 * Delete a model
 * @param modelIdentifier The model to delete
 */
suspend fun deleteModel(modelIdentifier: String) = withContext(Dispatchers.IO) {
    EventBus.publish(SDKModelEvent.DeleteStarted(modelIdentifier))

    try {
        // Use model manager to delete model
        ServiceContainer.shared.modelManager.deleteModel(modelIdentifier)
        EventBus.publish(SDKModelEvent.DeleteCompleted(modelIdentifier))
    } catch (error: Throwable) {
        EventBus.publish(SDKModelEvent.DeleteFailed(modelIdentifier, error))
        throw error
    }
}

/**
 * Add a custom model from URL - Complete implementation matching iOS functionality
 * @param url URL to the model
 * @param name Display name for the model
 * @param type Model type
 * @return Model information
 */
@OptIn(ExperimentalUuidApi::class)
suspend fun addModelFromURL(
    url: String,
    name: String,
    type: String
): ModelInfo = withContext(Dispatchers.IO) {
    logger.info("Adding custom model from URL: $url")
    EventBus.publish(SDKModelEvent.CustomModelAdded(name, url))

    try {
        // Parse model category from type string
        val modelCategory = when (type.lowercase()) {
            "llm", "language", "text" -> com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE
            "stt", "speech", "transcription" -> com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_RECOGNITION
            "tts", "voice", "synthesis" -> com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_SYNTHESIS
            else -> com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE // Default
        }

        // Create model info with comprehensive details
        val modelInfo = ModelInfo(
            id = Uuid.random().toString(),
            name = name,
            category = modelCategory,
            format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF, // Default to GGUF
            downloadURL = url,
            localPath = null,
            downloadSize = null,
            memoryRequired = 1024 * 1024 * 1024L, // Default 1GB
            compatibleFrameworks = listOf(com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP),
            preferredFramework = com.runanywhere.sdk.models.enums.LLMFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = com.runanywhere.sdk.models.ModelInfoMetadata(
                tags = listOf("custom", "url-added"),
                description = "Model added from URL: $url"
            )
        )

        // Register in model registry (in-memory)
        ServiceContainer.shared.modelRegistry.registerModel(modelInfo)
        logger.info("Model registered in registry: ${modelInfo.id}")

        // Save to persistent database via ModelInfoService
        try {
            ServiceContainer.shared.modelInfoService.saveModel(modelInfo)
            logger.info("Model saved to database: ${modelInfo.id}")
        } catch (dbError: Exception) {
            logger.warn("Failed to save model to database: ${dbError.message}")
            // Continue anyway - model is still in registry for this session
        }

        // Publish success event
        EventBus.publish(SDKModelEvent.CustomModelRegistered(modelInfo.id, url))
        
        logger.info("Successfully added custom model: ${modelInfo.name} (${modelInfo.id})")
        return@withContext modelInfo

    } catch (error: Exception) {
        logger.error("Failed to add model from URL: ${error.message}")
        EventBus.publish(SDKModelEvent.CustomModelFailed(name, url, error.message ?: "Unknown error"))
        throw SDKError.ModelRegistrationFailed("Failed to add model from URL: ${error.message}")
    }
}

/**
 * Register a built-in model
 * @param model The model to register
 */
suspend fun registerBuiltInModel(model: ModelInfo) = withContext(Dispatchers.IO) {
    // Register the model in the model registry
    ServiceContainer.shared.modelRegistry.registerModel(model)

    EventBus.publish(SDKModelEvent.BuiltInModelRegistered(model.id))
}

/**
 * Get currently loaded model from generation service
 */
fun getCurrentModel(): ModelInfo? {
    return ServiceContainer.shared.generationService.getCurrentModel()?.model
}

/**
 * Check if a model is currently loaded
 */
fun isModelLoaded(modelId: String): Boolean {
    return ServiceContainer.shared.modelLoadingService.isModelLoaded(modelId)
}

/**
 * Get total storage used by all models
 */
suspend fun getTotalModelsSize(): Long = withContext(Dispatchers.IO) {
    return@withContext ServiceContainer.shared.modelManager.getTotalModelsSize()
}

/**
 * Clear all models from storage
 */
suspend fun clearAllModels() = withContext(Dispatchers.IO) {
    ServiceContainer.shared.modelManager.clearAllModels()
}

/**
 * Check if a model is available locally
 */
fun isModelAvailable(modelId: String): Boolean {
    return ServiceContainer.shared.modelManager.isModelAvailable(modelId)
}