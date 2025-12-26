package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelArtifactType
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.storage.createFileSystem

/**
 * Model registry protocol - EXACT copy of iOS ModelRegistry
 */
interface ModelRegistry {
    /**
     * Discover available models
     * @return Array of discovered models
     */
    suspend fun discoverModels(): List<ModelInfo>

    /**
     * Register a model
     * @param model Model to register
     */
    fun registerModel(model: ModelInfo)

    /**
     * Get model by ID
     * @param id Model identifier
     * @return Model information if found
     */
    fun getModel(id: String): ModelInfo?

    /**
     * Update model information
     * @param model Updated model information
     */
    fun updateModel(model: ModelInfo)

    /**
     * Remove a model
     * @param id Model identifier
     */
    fun removeModel(id: String)

    /**
     * Get all registered models
     * @return All models in registry
     */
    fun getAllModels(): List<ModelInfo>

    /**
     * Check if a model is downloaded
     * @param id Model identifier
     * @return true if model is downloaded, false otherwise
     */
    fun isModelDownloaded(id: String): Boolean

    // Legacy methods for backward compatibility
    fun hasModel(id: String): Boolean = getModel(id) != null

    fun clearRegistry() = getAllModels().forEach { removeModel(it.id) }

    fun discoverModelsLegacy(): List<ModelInfo> = getAllModels()

    fun loadMockModels(mockModels: List<ModelInfo>) = mockModels.forEach { registerModel(it) }

    /**
     * Add a model from URL with inferred artifact type
     * Matches iOS ModelRegistry.addModelFromURL() convenience method
     */
    fun addModelFromURL(
        id: String? = null,
        name: String,
        url: String,
        framework: InferenceFramework,
        category: ModelCategory? = null,
        artifactType: ModelArtifactType? = null,
        estimatedSize: Long? = null,
        supportsThinking: Boolean = false,
    ): ModelInfo {
        // Infer format from URL using existing ModelFormat utility
        val format = ModelFormat.detectFromURL(url)

        // Create model info
        val modelInfo =
            ModelInfo(
                id = id ?: generateModelId(name, url),
                name = name,
                category = category ?: inferCategoryFromFramework(framework),
                format = format,
                downloadURL = url,
                artifactType = artifactType ?: ModelArtifactType.infer(url, format),
                downloadSize = estimatedSize,
                compatibleFrameworks = listOf(framework),
                preferredFramework = framework,
                supportsThinking = supportsThinking,
            )

        registerModel(modelInfo)
        return modelInfo
    }

    // Helper to generate model ID from name and URL
    private fun generateModelId(name: String, url: String): String {
        val sanitizedName = name.lowercase().replace(Regex("[^a-z0-9]"), "-")
        val urlHash = url.hashCode().toString(16).takeLast(6)
        return "$sanitizedName-$urlHash"
    }

    // Helper to infer category from framework (uses existing ModelCategory.from())
    private fun inferCategoryFromFramework(framework: InferenceFramework): ModelCategory = ModelCategory.from(framework)
}

/**
 * Default implementation of ModelRegistry - Thread-safe implementation matching iOS
 * Uses synchronized blocks for thread safety (matching iOS DispatchQueue pattern)
 */
class DefaultModelRegistry : ModelRegistry {
    private val models = mutableMapOf<String, ModelInfo>()
    private val lock = Any() // Lock object for synchronization (matches iOS concurrent queue)
    private val logger = SDKLogger("DefaultModelRegistry")
    private val fileSystem = createFileSystem()

    override suspend fun discoverModels(): List<ModelInfo> =
        synchronized(lock) {
            models.values.toList()
        }

    /**
     * Register a model - checks if already downloaded on disk and sets localPath
     * Matches iOS RegistryService.registerModel() behavior
     */
    override fun registerModel(model: ModelInfo) {
        synchronized(lock) {
            var updatedModel = model

            // If model doesn't have localPath, check if it exists on disk (like iOS)
            if (updatedModel.localPath == null) {
                val framework = model.preferredFramework ?: model.compatibleFrameworks.firstOrNull()
                if (framework != null) {
                    val localPath = findDownloadedModelPath(model.id, framework)
                    if (localPath != null) {
                        updatedModel = model.copy(localPath = localPath)
                        logger.info("Found downloaded model on disk: ${model.id} at $localPath")
                    }
                }
            }

            models[model.id] = updatedModel
        }
    }

    /**
     * Check if a model exists on disk and return its path
     * Matches iOS fileManager.modelFolderExists() + resolveModelPath()
     *
     * Directory structure follows iOS exactly:
     * {baseDir}/Models/{framework.value}/{modelId}/{modelId}.{format}
     * Example: Models/LlamaCpp/lfm2-350m-q4_k_m/lfm2-350m-q4_k_m.gguf
     */
    private fun findDownloadedModelPath(modelId: String, framework: InferenceFramework): String? {
        // 1. Check if the model folder exists: Models/{framework}/{modelId}/
        val modelFolder = ModelPathUtils.getModelFolder(modelId, framework)

        if (!fileSystem.existsSync(modelFolder)) {
            logger.debug("Model folder does not exist: $modelFolder")
            return null
        }

        // 2. Check for the expected model file: {modelFolder}/{modelId}.{ext}
        //    Common extensions: .gguf (LlamaCpp), .onnx (ONNX), .bin (general)
        val extensions =
            when (framework) {
                InferenceFramework.LLAMA_CPP -> listOf("gguf", "bin")
                InferenceFramework.ONNX -> listOf("onnx", "bin")
                InferenceFramework.WHISPER_KIT -> listOf("mlmodelc", "mlpackage")
                InferenceFramework.CORE_ML -> listOf("mlmodelc", "mlpackage")
                else -> listOf("bin", "gguf", "onnx")
            }

        for (ext in extensions) {
            val filePath = "$modelFolder/$modelId.$ext"
            if (fileSystem.existsSync(filePath)) {
                logger.debug("Found model file: $filePath")
                return filePath
            }
        }

        // 3. If no specific file found but folder exists, check if folder has contents
        //    Some models (like ONNX directories) are folder-based
        if (fileSystem.existsSync(modelFolder)) {
            logger.debug("Model folder exists but no specific file found, returning folder: $modelFolder")
            return modelFolder
        }

        return null
    }

    override fun getModel(id: String): ModelInfo? =
        synchronized(lock) {
            models[id]
        }

    override fun updateModel(model: ModelInfo) {
        synchronized(lock) {
            models[model.id] = model
        }
    }

    override fun removeModel(id: String) {
        synchronized(lock) {
            models.remove(id)
        }
    }

    override fun getAllModels(): List<ModelInfo> =
        synchronized(lock) {
            models.values.toList()
        }

    override fun isModelDownloaded(id: String): Boolean =
        synchronized(lock) {
            val model = models[id]
            model?.localPath != null
        }
}
