package com.runanywhere.sdk.models

import com.runanywhere.sdk.data.models.ModelInfo

/**
 * Central registry for model discovery and management
 */
class ModelRegistry {

    private val models = mutableMapOf<String, ModelInfo>()

    fun initialize() {
        // Initialize with known models
        // In production, this would fetch from a remote catalog
    }

    fun discoverModels(): List<ModelInfo> {
        return models.values.toList()
    }

    fun loadMockModels(mockModels: List<ModelInfo>) {
        mockModels.forEach { model ->
            models[model.id] = model
        }
    }

    fun getModel(id: String): ModelInfo? {
        return models[id]
    }

    fun registerModel(model: ModelInfo) {
        models[model.id] = model
    }

    fun hasModel(id: String): Boolean {
        return models.containsKey(id)
    }

    fun clearRegistry() {
        models.clear()
    }
}
