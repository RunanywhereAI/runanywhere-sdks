package com.runanywhere.sdk.models

import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelArtifactType
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Model criteria for filtering models - EXACT copy of iOS ModelCriteria
 */
data class ModelCriteria(
    val category: ModelCategory? = null,
    val framework: InferenceFramework? = null,
    val minMemoryRequired: Long? = null,
    val maxMemoryRequired: Long? = null,
    val format: String? = null,
    val isDownloaded: Boolean? = null,
)

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
     * Filter models by criteria
     * @param criteria Filter criteria
     * @return Filtered models
     */
    fun filterModels(criteria: ModelCriteria): List<ModelInfo>

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

    override suspend fun discoverModels(): List<ModelInfo> =
        synchronized(lock) {
            models.values.toList()
        }

    override fun registerModel(model: ModelInfo) {
        synchronized(lock) {
            models[model.id] = model
        }
    }

    override fun getModel(id: String): ModelInfo? =
        synchronized(lock) {
            models[id]
        }

    override fun filterModels(criteria: ModelCriteria): List<ModelInfo> =
        synchronized(lock) {
            models.values.filter { model ->
                var matches = true

                criteria.category?.let { category ->
                    matches = matches && model.category == category
                }

                criteria.framework?.let { framework ->
                    matches = matches &&
                        (
                            model.preferredFramework == framework ||
                                model.compatibleFrameworks.contains(framework)
                        )
                }

                criteria.minMemoryRequired?.let { minMemory ->
                    matches = matches && (model.memoryRequired ?: 0L) >= minMemory
                }

                criteria.maxMemoryRequired?.let { maxMemory ->
                    matches = matches && (model.memoryRequired ?: Long.MAX_VALUE) <= maxMemory
                }

                criteria.format?.let { format ->
                    matches = matches && model.format.name.equals(format, ignoreCase = true)
                }

                criteria.isDownloaded?.let { downloaded ->
                    matches = matches && (model.localPath != null) == downloaded
                }

                matches
            }
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
