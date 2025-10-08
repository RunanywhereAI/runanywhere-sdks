package com.runanywhere.sdk.models

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

        // Check memory availability
        val memoryRequired = modelInfo.memoryRequired ?: (1024 * 1024 * 1024L) // Default 1GB if not specified
        val canAllocate = memoryService.canAllocate(memoryRequired)
        if (!canAllocate) {
            throw SDKError.LoadingFailed("Insufficient memory")
        }

        // For now, create a mock service until LLM adapters are implemented
        logger.info("🚀 Creating mock service for model (real adapter integration pending)")
        val mockService = MockLLMService(modelInfo)

        // Create loaded model
        val loaded = LoadedModelWithService(
            model = modelInfo,
            service = mockService,
            localPath = modelInfo.localPath,
            loadedAt = System.currentTimeMillis()
        )

        // Register loaded model with memory service
        memoryService.registerLoadedModel(
            modelId = loaded.model.id,
            size = modelInfo.memoryRequired ?: memoryRequired,
            service = mockService
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

        // Cleanup service
        if (loaded.service is MockLLMService) {
            loaded.service.cleanup()
        }

        // Unregister from memory service
        memoryService.unregisterModel(modelId)

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

/**
 * Mock LLM Service for development until real adapters are implemented
 */
private class MockLLMService(
    private val modelInfo: ModelInfo
) {
    private val logger = SDKLogger("MockLLMService")

    init {
        logger.info("MockLLMService created for model: ${modelInfo.id}")
    }

    suspend fun cleanup() {
        logger.info("MockLLMService cleanup for model: ${modelInfo.id}")
    }

    fun getCurrentModel(): ModelInfo = modelInfo
}
