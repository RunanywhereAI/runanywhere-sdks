package com.runanywhere.sdk.foundation.utils

import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Centralized utility for model path calculations.
 *
 * IMPORTANT: This is the SINGLE SOURCE OF TRUTH for model path CALCULATIONS in the SDK.
 *
 * ## Responsibilities
 * - Calculate expected paths based on conventions
 * - Provide path analysis utilities
 * - Directory structure constants
 *
 * ## NOT Responsible For (handled by ModelStorageStrategy per-module)
 * - Finding actual model files within directories
 * - Validating model content
 * - Model type/format detection
 *
 * ## Directory Structure
 * ```
 * {baseDir}/models/{framework}/{modelId}/
 *   └── {model files - structure varies by framework}
 * ```
 *
 * ## Usage Pattern
 * 1. Use ModelPathUtils.getModelFolder() to get expected location
 * 2. Use ModuleRegistry.storageStrategy(framework).findModelPath() to resolve actual path
 * 3. Use ModuleRegistry.storageStrategy(framework).isValidModelStorage() to validate
 *
 * Example Android: /data/data/app/files/runanywhere/models/LlamaCpp/lfm2-350m-q4-k-m/
 * Example iOS: {Documents}/RunAnywhere/Models/{framework}/{modelId}/
 */
object ModelPathUtils {
    // ============================================================
    // MARK: - Base Directories
    // ============================================================

    /**
     * Get the base RunAnywhere directory
     * iOS equivalent: Documents/RunAnywhere/
     * Android equivalent: filesDir/runanywhere/
     */
    fun getBaseDirectory(): String = SimplifiedFileManager.shared.baseDirectory.toString()

    /**
     * Get the models directory
     * This is where all downloaded models are stored
     * Pattern: {baseDir}/Models/
     */
    fun getModelsDirectory(): String = SimplifiedFileManager.shared.modelsDirectory.toString()

    // ============================================================
    // MARK: - Framework-Specific Paths
    // ============================================================

    /**
     * Get the directory for a specific framework
     * Pattern: {modelsDir}/{framework.value}/
     * Example: Models/ONNX/
     */
    fun getFrameworkDirectory(framework: InferenceFramework): String {
        val modelsDir = getModelsDirectory()
        return "$modelsDir/${framework.value}"
    }

    /**
     * Get the folder for a specific model with framework
     * Pattern: {modelsDir}/{framework.value}/{modelId}/
     * Example: Models/ONNX/sherpa-whisper-tiny-onnx/
     *
     * @param modelId The unique model identifier
     * @param framework The framework the model is associated with
     * @return The full path to the model folder
     */
    fun getModelFolder(
        modelId: String,
        framework: InferenceFramework,
    ): String {
        val modelsDir = getModelsDirectory()
        return "$modelsDir/${framework.value}/$modelId"
    }

    /**
     * Get the folder for a specific model (legacy path without framework)
     * Pattern: {modelsDir}/{modelId}/
     * Example: Models/sherpa-whisper-tiny-onnx/
     *
     * Note: Prefer using the framework-specific version when framework is known
     *
     * @param modelId The unique model identifier
     * @return The full path to the model folder
     */
    fun getModelFolder(modelId: String): String {
        val modelsDir = getModelsDirectory()
        return "$modelsDir/$modelId"
    }

    // ============================================================
    // MARK: - Model File Paths
    // ============================================================

    /**
     * Get the full file path for a model with framework
     * Pattern: {modelsDir}/{framework.value}/{modelId}/{modelId}.{format}
     * Example: Models/ONNX/sherpa-whisper-tiny-onnx/sherpa-whisper-tiny-onnx.onnx
     *
     * @param modelId The unique model identifier
     * @param framework The framework the model is associated with
     * @param format The model format (determines file extension)
     * @return The full path to the model file
     */
    fun getModelFilePath(
        modelId: String,
        framework: InferenceFramework,
        format: ModelFormat,
    ): String {
        val folder = getModelFolder(modelId, framework)
        val extension = format.value
        return "$folder/$modelId.$extension"
    }

    /**
     * Get the full file path for a model (legacy path without framework)
     * Pattern: {modelsDir}/{modelId}/{modelId}.{format}
     *
     * @param modelId The unique model identifier
     * @param format The model format (determines file extension)
     * @return The full path to the model file
     */
    fun getModelFilePath(
        modelId: String,
        format: ModelFormat,
    ): String {
        val folder = getModelFolder(modelId)
        val extension = format.value
        return "$folder/$modelId.$extension"
    }

    /**
     * Get the model path from a ModelInfo object
     * Uses the preferred framework or first compatible framework
     *
     * @param modelInfo The model information object
     * @return The full path to the model file
     */
    fun getModelPath(modelInfo: ModelInfo): String {
        val framework =
            modelInfo.preferredFramework
                ?: modelInfo.compatibleFrameworks.firstOrNull()

        return if (framework != null) {
            getModelFilePath(modelInfo.id, framework, modelInfo.format)
        } else {
            getModelFilePath(modelInfo.id, modelInfo.format)
        }
    }

    /**
     * Get the expected model path from components
     * Convenience method when you have the individual components
     *
     * @param modelId The unique model identifier
     * @param framework Optional framework (uses legacy path if null)
     * @param format The model format
     * @return The full path to the expected model file
     */
    fun getExpectedModelPath(
        modelId: String,
        framework: InferenceFramework?,
        format: ModelFormat,
    ): String =
        if (framework != null) {
            getModelFilePath(modelId, framework, format)
        } else {
            getModelFilePath(modelId, format)
        }

    // ============================================================
    // MARK: - Other Directories
    // ============================================================

    /**
     * Get the cache directory for SDK operations
     */
    fun getCacheDirectory(): String = SimplifiedFileManager.shared.cacheDirectory.toString()

    /**
     * Get the temporary directory for downloads and processing
     */
    fun getTempDirectory(): String = SimplifiedFileManager.shared.temporaryDirectory.toString()

    /**
     * Get the downloads directory for in-progress downloads
     */
    fun getDownloadsDirectory(): String = SimplifiedFileManager.shared.downloadsDirectory.toString()

    // ============================================================
    // MARK: - Path Analysis Utilities
    // ============================================================

    /**
     * Extract the model ID from a path
     * Works with both framework and non-framework paths
     *
     * @param path The path to analyze
     * @return The model ID if found, null otherwise
     */
    fun extractModelId(path: String): String? {
        val modelsDir = getModelsDirectory()
        if (!path.startsWith(modelsDir)) return null

        val relativePath = path.removePrefix(modelsDir).trim('/')
        val components = relativePath.split("/")

        // Check for framework path: {framework}/{modelId}/...
        // or legacy path: {modelId}/...
        return when {
            components.size >= 2 -> {
                // Could be framework/modelId or modelId/file
                val possibleFramework = InferenceFramework.entries.find { it.value == components[0] }
                if (possibleFramework != null && components.size >= 2) {
                    components[1] // It's a framework path, modelId is second
                } else {
                    components[0] // It's a legacy path, modelId is first
                }
            }
            components.size == 1 -> components[0]
            else -> null
        }
    }

    /**
     * Extract the framework from a path
     *
     * @param path The path to analyze
     * @return The framework if found, null otherwise
     */
    fun extractFramework(path: String): InferenceFramework? {
        val modelsDir = getModelsDirectory()
        if (!path.startsWith(modelsDir)) return null

        val relativePath = path.removePrefix(modelsDir).trim('/')
        val firstComponent = relativePath.split("/").firstOrNull() ?: return null

        return InferenceFramework.entries.find { it.value == firstComponent }
    }

    /**
     * Check if a path is within the models directory
     *
     * @param path The path to check
     * @return True if the path is within the models directory
     */
    fun isModelPath(path: String): Boolean = path.startsWith(getModelsDirectory())

    // ============================================================
    // MARK: - Common Model Paths (for model discovery)
    // ============================================================

    /**
     * Get all possible paths where a model might be located
     * Useful for model discovery when framework is unknown
     *
     * @param modelId The model ID to search for
     * @return List of possible paths to check
     */
    fun getPossibleModelPaths(modelId: String): List<String> {
        val modelsDir = getModelsDirectory()
        return listOf(
            // Legacy path
            "$modelsDir/$modelId",
            // Framework-specific paths
            "$modelsDir/${InferenceFramework.LLAMA_CPP.value}/$modelId",
            "$modelsDir/${InferenceFramework.ONNX.value}/$modelId",
            "$modelsDir/${InferenceFramework.WHISPER_KIT.value}/$modelId",
            "$modelsDir/${InferenceFramework.CORE_ML.value}/$modelId",
            "$modelsDir/${InferenceFramework.MLC.value}/$modelId",
        )
    }

    /**
     * Get all possible file paths where a model file might be located
     * Includes common extensions
     *
     * @param modelId The model ID to search for
     * @return List of possible file paths to check
     */
    fun getPossibleModelFilePaths(modelId: String): List<String> {
        val modelsDir = getModelsDirectory()
        val extensions = listOf("gguf", "bin", "onnx", "mlmodelc", "mlpackage")
        val frameworks = InferenceFramework.entries.map { it.value }

        val paths = mutableListOf<String>()

        // Legacy paths
        for (ext in extensions) {
            paths.add("$modelsDir/$modelId/$modelId.$ext")
        }

        // Framework-specific paths
        for (framework in frameworks) {
            for (ext in extensions) {
                paths.add("$modelsDir/$framework/$modelId/$modelId.$ext")
            }
        }

        return paths
    }
}
