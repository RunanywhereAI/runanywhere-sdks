package com.runanywhere.sdk.models

import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.LoadedModel
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.memory.MemoryManager
import com.runanywhere.sdk.storage.FileSystem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * LoadedModel enhanced with service reference - EXACT copy of iOS LoadedModel
 */
data class LoadedModelWithService(
    val model: ModelInfo,
    val service: Any, // Would be LLMService in production
    val localPath: String? = null,
    val loadedAt: Long = System.currentTimeMillis()
)

/**
 * Service responsible for loading models - EXACT copy of iOS ModelLoadingService
 */
class ModelLoadingService(
    private val registry: ModelRegistry,
    private val memoryService: MemoryManager,
    private val fileSystem: FileSystem
) {
    private val logger = SDKLogger("ModelLoadingService")
    private val loadedModels = mutableMapOf<String, LoadedModelWithService>()

    /**
     * Load a model by identifier - EXACT copy of iOS implementation
     */
    suspend fun loadModel(modelId: String): LoadedModelWithService = withContext(Dispatchers.Default) {
        logger.info("🚀 Loading model: $modelId")

        // Check if already loaded
        loadedModels[modelId]?.let { loaded ->
            logger.info("✅ Model already loaded: $modelId")
            return@withContext loaded
        }

        // Get model info from registry
        val modelInfo = registry.getModel(modelId)
            ?: run {
                logger.error("❌ Model not found in registry: $modelId")
                throw SDKError.ModelNotFound(modelId)
            }

        logger.info("✅ Found model in registry: ${modelInfo.name}")

        // Check if this is a built-in model (e.g., Foundation Models)
        val isBuiltIn = modelInfo.localPath?.toString()?.startsWith("builtin") == true

        if (!isBuiltIn) {
            // Check model file exists for non-built-in models
            if (modelInfo.localPath == null) {
                throw SDKError.ModelNotFound("Model '$modelId' not downloaded")
            }

            // Verify file exists on filesystem
            modelInfo.localPath?.let { path ->
                if (!fileSystem.exists(path)) {
                    throw SDKError.ModelNotFound("Model file not found at path: $path")
                }
            }
        } else {
            logger.info("🏗️ Built-in model detected, skipping file check")
        }

        // Get the appropriate LLM provider for this model
        val provider = ModuleRegistry.llmProvider(modelId)
            ?: throw SDKError.LoadingFailed("No LLM provider available for model: $modelId")

        logger.info("🚀 Using LLM provider: ${provider.name} for model: $modelId")

        // Create LLMConfiguration from ModelInfo
        val configuration = com.runanywhere.sdk.features.llm.LLMConfiguration(
            modelId = modelInfo.localPath ?: modelInfo.id,
            contextLength = modelInfo.contextLength ?: 2048,
            useGPUIfAvailable = true,
            streamingEnabled = true
        )

        // Create the actual LLM service using the provider
        val llmService = try {
            provider.createLLMService(configuration)
        } catch (e: Exception) {
            logger.error("❌ Failed to create LLM service: ${e.message}")
            throw SDKError.LoadingFailed("Failed to create LLM service: ${e.message}")
        }

        // Initialize the LLM service with the model path
        // iOS pattern: service is initialized via initialize(modelPath), not loadModel
        try {
            llmService.initialize(modelInfo.localPath)
            logger.info("✅ LLM service initialized with model: $modelId")
        } catch (e: Exception) {
            logger.error("❌ Failed to initialize LLM service: ${e.message}")
            throw SDKError.LoadingFailed("Failed to initialize model: ${e.message}")
        }

        // Create loaded model
        val loaded = LoadedModelWithService(
            model = modelInfo,
            service = llmService,
            localPath = modelInfo.localPath,
            loadedAt = System.currentTimeMillis()
        )

        loadedModels[modelId] = loaded

        logger.info("✅ Model loaded successfully: $modelId")
        return@withContext loaded
    }

    /**
     * Unload a model - EXACT copy of iOS implementation
     */
    suspend fun unloadModel(modelId: String) = withContext(Dispatchers.Default) {
        val loaded = loadedModels[modelId] ?: return@withContext

        // Cleanup LLM service
        if (loaded.service is LLMService) {
            try {
                // LLMService doesn't have a cleanup method, just let it be garbage collected
                logger.info("🗑️ Releasing LLM service for model: $modelId")
            } catch (e: Exception) {
                logger.error("⚠️ Error during service cleanup: ${e.message}")
            }
        }

        // Remove from loaded models
        loadedModels.remove(modelId)

        logger.info("✅ Model unloaded: $modelId")
    }

    /**
     * Get currently loaded model - EXACT copy of iOS implementation
     */
    fun getLoadedModel(modelId: String): LoadedModelWithService? {
        return loadedModels[modelId]
    }

    /**
     * Check if model is loaded
     */
    fun isModelLoaded(modelId: String): Boolean {
        return loadedModels.containsKey(modelId)
    }

    /**
     * Get all loaded models
     */
    fun getAllLoadedModels(): List<LoadedModelWithService> {
        return loadedModels.values.toList()
    }

    /**
     * Clear all loaded models
     */
    suspend fun clearAllModels() = withContext(Dispatchers.Default) {
        val modelIds = loadedModels.keys.toList()
        for (modelId in modelIds) {
            unloadModel(modelId)
        }
        logger.info("✅ All models unloaded")
    }
}
