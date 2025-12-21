package com.runanywhere.sdk.infrastructure.modelmanagement.services

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.storage.FileSystem
import com.runanywhere.sdk.storage.createFileSystem

/**
 * Service for discovering locally stored and bundled models
 * Matches iOS RegistryService.discoverFrameworkModels() and discoverBundleModels()
 *
 * Scans the filesystem for models that were downloaded but may not be in the database,
 * and discovers bundled models included in the app resources.
 */
class ModelDiscoveryService(
    private val fileSystem: FileSystem = createFileSystem(),
) {
    private val logger = SDKLogger("ModelDiscoveryService")

    companion object {
        /**
         * Known model file extensions mapped to their formats
         * Matches iOS modelExtensions in RegistryService
         */
        private val EXTENSION_TO_FORMAT =
            mapOf(
                "gguf" to ModelFormat.GGUF,
                "ggml" to ModelFormat.GGUF,
                "bin" to ModelFormat.BIN,
                "onnx" to ModelFormat.ONNX,
                "mlmodel" to ModelFormat.MLMODEL,
                "mlmodelc" to ModelFormat.MLMODEL, // Compiled CoreML model
                "mlpackage" to ModelFormat.MLMODEL,
                "tflite" to ModelFormat.TFLITE,
                "safetensors" to ModelFormat.SAFETENSORS,
                "pte" to ModelFormat.PTE, // ExecuTorch
            )

        /**
         * Framework-to-category mapping for inferring model category
         */
        private val FRAMEWORK_DEFAULT_CATEGORY =
            mapOf(
                InferenceFramework.LLAMA_CPP to ModelCategory.LANGUAGE,
                InferenceFramework.WHISPER_KIT to ModelCategory.SPEECH_RECOGNITION,
                InferenceFramework.WHISPER_CPP to ModelCategory.SPEECH_RECOGNITION,
                InferenceFramework.ONNX to ModelCategory.OTHER, // Could be any
                InferenceFramework.CORE_ML to ModelCategory.OTHER,
            )
    }

    // MARK: - Discovery Methods

    /**
     * Discover all locally available models
     * Matches iOS RegistryService.discoverLocalModels()
     *
     * @return List of discovered ModelInfo objects
     */
    suspend fun discoverAllLocalModels(): List<ModelInfo> {
        logger.info("Starting local model discovery...")

        val frameworkModels = discoverFrameworkModels()
        val bundleModels = discoverBundleModels()

        val allModels = (frameworkModels + bundleModels).distinctBy { it.id }

        logger.info("Discovered ${allModels.size} local models (${frameworkModels.size} framework, ${bundleModels.size} bundle)")

        return allModels
    }

    /**
     * Discover models organized by framework
     * Matches iOS RegistryService.discoverFrameworkModels()
     *
     * Scans: {modelsDir}/{framework}/{modelId}/ directories
     */
    suspend fun discoverFrameworkModels(): List<ModelInfo> {
        val modelsDir = ModelPathUtils.getModelsDirectory()

        if (!fileSystem.exists(modelsDir)) {
            logger.debug("Models directory does not exist: $modelsDir")
            return emptyList()
        }

        val discoveredModels = mutableListOf<ModelInfo>()

        // For each framework, scan its directory
        for (framework in InferenceFramework.entries) {
            val frameworkDir = ModelPathUtils.getFrameworkDirectory(framework)

            if (!fileSystem.exists(frameworkDir)) {
                continue
            }

            if (!fileSystem.isDirectory(frameworkDir)) {
                continue
            }

            logger.debug("Scanning framework directory: ${framework.displayName}")

            try {
                val modelFolders = fileSystem.listFiles(frameworkDir)

                for (modelId in modelFolders) {
                    val modelFolder = "$frameworkDir/$modelId"

                    if (!fileSystem.isDirectory(modelFolder)) {
                        continue
                    }

                    // Try to discover model in this folder
                    val modelInfo =
                        discoverModelInFolder(
                            modelId = modelId,
                            modelFolder = modelFolder,
                            framework = framework,
                        )

                    if (modelInfo != null) {
                        discoveredModels.add(modelInfo)
                        logger.debug("Discovered model: $modelId (${framework.displayName})")
                    }
                }
            } catch (e: Exception) {
                logger.warn("Error scanning framework directory ${framework.displayName}: ${e.message}")
            }
        }

        // Also scan legacy path (models directly in modelsDir without framework subfolder)
        discoveredModels.addAll(discoverLegacyModels(modelsDir))

        return discoveredModels
    }

    /**
     * Discover models in the legacy path (without framework subfolder)
     * These are models stored directly in modelsDir/{modelId}/
     */
    private suspend fun discoverLegacyModels(modelsDir: String): List<ModelInfo> {
        val discoveredModels = mutableListOf<ModelInfo>()

        try {
            val entries = fileSystem.listFiles(modelsDir)

            for (entry in entries) {
                // Skip framework directories (already scanned)
                val isFrameworkDir = InferenceFramework.entries.any { it.value == entry }
                if (isFrameworkDir) continue

                val modelFolder = "$modelsDir/$entry"

                if (!fileSystem.isDirectory(modelFolder)) {
                    continue
                }

                // Try to discover model in this folder (no specific framework)
                val modelInfo =
                    discoverModelInFolder(
                        modelId = entry,
                        modelFolder = modelFolder,
                        framework = null,
                    )

                if (modelInfo != null) {
                    discoveredModels.add(modelInfo)
                    logger.debug("Discovered legacy model: $entry")
                }
            }
        } catch (e: Exception) {
            logger.warn("Error scanning legacy models directory: ${e.message}")
        }

        return discoveredModels
    }

    /**
     * Discover a model within a specific folder
     * Uses storage strategies if available, otherwise uses generic detection
     *
     * @param modelId The model ID (folder name)
     * @param modelFolder Full path to the model folder
     * @param framework Optional framework (for framework-specific detection)
     * @return ModelInfo if a valid model is found, null otherwise
     */
    private suspend fun discoverModelInFolder(
        modelId: String,
        modelFolder: String,
        framework: InferenceFramework?,
    ): ModelInfo? {
        // Try framework-specific storage strategy first
        if (framework != null) {
            val storageStrategy = ModuleRegistry.getStorageStrategy(framework)

            if (storageStrategy != null) {
                try {
                    val detection = storageStrategy.detectModel(modelFolder)

                    if (detection != null) {
                        val modelPath = storageStrategy.findModelPath(modelId, modelFolder)

                        return createModelInfo(
                            modelId = modelId,
                            localPath = modelPath ?: modelFolder,
                            format = detection.format,
                            downloadSize = detection.size,
                            framework = framework,
                        )
                    }
                } catch (e: Exception) {
                    logger.debug("Storage strategy detection failed for $modelId: ${e.message}")
                }
            }
        }

        // Fallback: Generic file-based detection
        return detectModelInFolderGeneric(modelId, modelFolder, framework)
    }

    /**
     * Generic model detection by scanning folder for known model file extensions
     * Matches iOS detectModelInFolder() fallback logic
     */
    private suspend fun detectModelInFolderGeneric(
        modelId: String,
        modelFolder: String,
        framework: InferenceFramework?,
    ): ModelInfo? {
        try {
            val files = fileSystem.listFiles(modelFolder)

            for (filename in files) {
                val extension = filename.substringAfterLast('.', "").lowercase()
                val format = EXTENSION_TO_FORMAT[extension] ?: continue

                val filePath = "$modelFolder/$filename"

                // Skip directories (e.g., .mlmodelc is a directory)
                // For .mlmodelc and .mlpackage, we check if they exist
                val isModelFile =
                    if (extension in listOf("mlmodelc", "mlpackage")) {
                        fileSystem.exists(filePath)
                    } else {
                        !fileSystem.isDirectory(filePath)
                    }

                if (!isModelFile) continue

                val size =
                    try {
                        if (fileSystem.isDirectory(filePath)) {
                            calculateDirectorySize(filePath)
                        } else {
                            fileSystem.fileSize(filePath)
                        }
                    } catch (e: Exception) {
                        0L
                    }

                return createModelInfo(
                    modelId = modelId,
                    localPath = filePath,
                    format = format,
                    downloadSize = size,
                    framework = framework ?: inferFramework(format),
                )
            }
        } catch (e: Exception) {
            logger.debug("Error detecting model in $modelFolder: ${e.message}")
        }

        return null
    }

    /**
     * Calculate total size of a directory (for multi-file models like .mlmodelc)
     */
    private suspend fun calculateDirectorySize(dirPath: String): Long {
        var totalSize = 0L

        try {
            val files = fileSystem.listFiles(dirPath)

            for (filename in files) {
                val filePath = "$dirPath/$filename"

                if (fileSystem.isDirectory(filePath)) {
                    totalSize += calculateDirectorySize(filePath)
                } else {
                    totalSize += fileSystem.fileSize(filePath)
                }
            }
        } catch (e: Exception) {
            logger.debug("Error calculating directory size for $dirPath: ${e.message}")
        }

        return totalSize
    }

    /**
     * Discover models bundled with the application
     * Platform-specific implementation - uses expect/actual pattern
     */
    suspend fun discoverBundleModels(): List<ModelInfo> {
        // Bundle discovery is platform-specific
        // Android: Use AssetManager to scan assets
        // JVM: Use ClassLoader.getResources()
        // Native: Scan resource directories

        val bundleModels = discoverBundleModelsPlatform()
        logger.debug("Discovered ${bundleModels.size} bundled models")
        return bundleModels
    }

    // MARK: - Helper Methods

    /**
     * Create a ModelInfo from discovered data
     */
    private fun createModelInfo(
        modelId: String,
        localPath: String,
        format: ModelFormat,
        downloadSize: Long,
        framework: InferenceFramework,
    ): ModelInfo {
        // Infer category from framework or model ID
        val category = inferCategory(modelId, framework)

        return ModelInfo(
            id = modelId,
            name = modelId.replace("-", " ").replace("_", " "),
            category = category,
            format = format,
            localPath = localPath,
            downloadSize = downloadSize,
            memoryRequired = estimateMemoryRequired(downloadSize, format),
            compatibleFrameworks = listOf(framework),
            preferredFramework = framework,
            source = ConfigurationSource.LOCAL,
            metadata =
                ModelInfoMetadata(
                    description = "Locally discovered model",
                    version = "1.0.0",
                ),
        )
    }

    /**
     * Infer the framework from model format
     */
    private fun inferFramework(format: ModelFormat): InferenceFramework =
        when (format) {
            ModelFormat.GGUF -> InferenceFramework.LLAMA_CPP
            ModelFormat.ONNX -> InferenceFramework.ONNX
            ModelFormat.MLMODEL -> InferenceFramework.CORE_ML
            ModelFormat.TFLITE -> InferenceFramework.TENSORFLOW_LITE
            ModelFormat.SAFETENSORS -> InferenceFramework.MLC
            else -> InferenceFramework.UNKNOWN
        }

    /**
     * Infer model category from model ID and framework
     */
    private fun inferCategory(
        modelId: String,
        framework: InferenceFramework,
    ): ModelCategory {
        // Check model ID patterns
        val lowerModelId = modelId.lowercase()

        return when {
            lowerModelId.contains("whisper") -> ModelCategory.SPEECH_RECOGNITION
            lowerModelId.contains("stt") -> ModelCategory.SPEECH_RECOGNITION
            lowerModelId.contains("tts") -> ModelCategory.SPEECH_SYNTHESIS
            lowerModelId.contains("voice") -> ModelCategory.SPEECH_RECOGNITION
            lowerModelId.contains("llama") -> ModelCategory.LANGUAGE
            lowerModelId.contains("llm") -> ModelCategory.LANGUAGE
            lowerModelId.contains("gpt") -> ModelCategory.LANGUAGE
            lowerModelId.contains("mistral") -> ModelCategory.LANGUAGE
            lowerModelId.contains("phi") -> ModelCategory.LANGUAGE
            lowerModelId.contains("qwen") -> ModelCategory.LANGUAGE
            lowerModelId.contains("gemma") -> ModelCategory.LANGUAGE
            lowerModelId.contains("vision") -> ModelCategory.VISION
            lowerModelId.contains("vlm") -> ModelCategory.VISION
            lowerModelId.contains("vad") -> ModelCategory.OTHER
            lowerModelId.contains("speaker") -> ModelCategory.OTHER
            lowerModelId.contains("diarization") -> ModelCategory.OTHER
            else -> FRAMEWORK_DEFAULT_CATEGORY[framework] ?: ModelCategory.OTHER
        }
    }

    /**
     * Estimate memory required based on download size and format
     */
    private fun estimateMemoryRequired(
        downloadSize: Long,
        format: ModelFormat,
    ): Long {
        // Memory requirement depends on format:
        // - GGUF (quantized): ~1.5x download size
        // - ONNX: ~2x download size
        // - CoreML: ~1.5x download size
        // - SafeTensors: ~2x download size

        val multiplier =
            when (format) {
                ModelFormat.GGUF -> 1.5
                ModelFormat.ONNX -> 2.0
                ModelFormat.MLMODEL -> 1.5
                ModelFormat.SAFETENSORS -> 2.0
                ModelFormat.TFLITE -> 1.5
                else -> 2.0
            }

        return (downloadSize * multiplier).toLong()
    }

    /**
     * Get format from file extension
     */
    fun getFormatFromExtension(extension: String): ModelFormat? = EXTENSION_TO_FORMAT[extension.lowercase()]

    /**
     * Get all known model file extensions
     */
    fun getKnownModelExtensions(): List<String> = EXTENSION_TO_FORMAT.keys.toList()
}

// MARK: - Platform-Specific Bundle Discovery

/**
 * Platform-specific implementation for bundle model discovery
 * Each platform implements this using their resource loading APIs
 */
expect suspend fun discoverBundleModelsPlatform(): List<ModelInfo>
