package com.runanywhere.sdk.models

import java.io.File

/**
 * Model storage manager for handling model files
 */
class ModelStorage {
    companion object {
        private val baseDir = File(System.getProperty("user.home"), ".runanywhere")
        private val modelsDir = File(baseDir, "models")

        init {
            modelsDir.mkdirs()
        }

        fun getModelDestination(modelId: String): File {
            return File(modelsDir, "$modelId.bin")
        }
    }

    /**
     * Get the path of a model if it exists
     */
    fun getModelPath(modelId: String): File? {
        val modelFile = getModelDestination(modelId)
        return if (modelFile.exists()) modelFile else null
    }

    /**
     * Delete a model file
     */
    fun deleteModel(modelId: String) {
        val modelFile = getModelDestination(modelId)
        if (modelFile.exists()) {
            modelFile.delete()
        }
    }

    /**
     * Get total size of all models
     */
    fun getTotalModelsSize(): Long {
        return modelsDir.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }

    /**
     * List all stored models
     */
    fun listStoredModels(): List<String> {
        return modelsDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".bin") }
            ?.map { it.nameWithoutExtension }
            ?: emptyList()
    }

    /**
     * Clear all models
     */
    fun clearAllModels() {
        modelsDir.walkTopDown()
            .filter { it.isFile }
            .forEach { it.delete() }
    }
}
