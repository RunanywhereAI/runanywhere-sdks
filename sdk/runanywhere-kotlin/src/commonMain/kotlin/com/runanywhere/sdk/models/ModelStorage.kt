package com.runanywhere.sdk.models

/**
 * Platform-specific file operations
 */
expect class PlatformFile {
    val path: String
    fun exists(): Boolean
    fun delete(): Boolean
    fun length(): Long
    val name: String
    val nameWithoutExtension: String
    fun isFile(): Boolean
}

expect fun createPlatformFile(path: String): PlatformFile
expect fun getPlatformBaseDir(): String
expect fun createDirectory(path: String): Boolean
expect fun listFiles(directory: String): List<PlatformFile>

/**
 * Model storage manager for handling model files
 */
class ModelStorage {
    companion object {
        private val baseDir = getPlatformBaseDir()
        private val modelsDir = "$baseDir/models"

        init {
            createDirectory(modelsDir)
        }

        fun getModelDestination(modelId: String): String {
            return "$modelsDir/$modelId.bin"
        }
    }

    /**
     * Get the path of a model if it exists
     */
    fun getModelPath(modelId: String): String? {
        val modelPath = getModelDestination(modelId)
        val modelFile = createPlatformFile(modelPath)
        return if (modelFile.exists()) modelPath else null
    }

    /**
     * Delete a model file
     */
    fun deleteModel(modelId: String) {
        val modelPath = getModelDestination(modelId)
        val modelFile = createPlatformFile(modelPath)
        if (modelFile.exists()) {
            modelFile.delete()
        }
    }

    /**
     * Get total size of all models
     */
    fun getTotalModelsSize(): Long {
        return listFiles(modelsDir)
            .filter { it.isFile() }
            .sumOf { it.length() }
    }

    /**
     * List all stored models
     */
    fun listStoredModels(): List<String> {
        return listFiles(modelsDir)
            .filter { it.isFile() && it.name.endsWith(".bin") }
            .map { it.nameWithoutExtension }
    }

    /**
     * Clear all models
     */
    fun clearAllModels() {
        listFiles(modelsDir)
            .filter { it.isFile() }
            .forEach { it.delete() }
    }
}
