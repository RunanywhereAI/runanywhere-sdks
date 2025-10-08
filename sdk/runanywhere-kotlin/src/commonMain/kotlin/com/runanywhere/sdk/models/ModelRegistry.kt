package com.runanywhere.sdk.models

import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.LLMFramework

/**
 * Model criteria for filtering models - EXACT copy of iOS ModelCriteria
 */
data class ModelCriteria(
    val category: ModelCategory? = null,
    val framework: LLMFramework? = null,
    val minMemoryRequired: Long? = null,
    val maxMemoryRequired: Long? = null,
    val format: String? = null,
    val isDownloaded: Boolean? = null
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
}

/**
 * Default implementation of ModelRegistry - EXACT copy of iOS DefaultModelRegistry
 */
class DefaultModelRegistry : ModelRegistry {
    private val models = mutableMapOf<String, ModelInfo>()

    override suspend fun discoverModels(): List<ModelInfo> {
        return models.values.toList()
    }

    override fun registerModel(model: ModelInfo) {
        models[model.id] = model
    }

    override fun getModel(id: String): ModelInfo? {
        return models[id]
    }

    override fun filterModels(criteria: ModelCriteria): List<ModelInfo> {
        return models.values.filter { model ->
            var matches = true
            
            criteria.category?.let { category ->
                matches = matches && model.category == category
            }
            
            criteria.framework?.let { framework ->
                matches = matches && (model.preferredFramework == framework || 
                                    model.compatibleFrameworks.contains(framework))
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
        models[model.id] = model
    }

    override fun removeModel(id: String) {
        models.remove(id)
    }

    override fun getAllModels(): List<ModelInfo> {
        return models.values.toList()
    }

    override fun isModelDownloaded(id: String): Boolean {
        val model = models[id]
        return model?.localPath != null
    }
}
