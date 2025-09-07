package com.runanywhere.sdk.files

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.download.FileManager
import com.runanywhere.sdk.utils.getCurrentTimeMillis

/**
 * Default file manager implementation
 * Matches iOS SimplifiedFileManager pattern
 */
class FileManagerImpl : FileManager {

    private val logger = SDKLogger("FileManager")

    companion object {
        // Directory structure matching iOS
        const val ROOT_FOLDER = "RunAnywhere"
        const val MODELS_FOLDER = "Models"
        const val CACHE_FOLDER = "Cache"
        const val TEMP_FOLDER = "Temp"
        const val DOWNLOADS_FOLDER = "Downloads"

        // Supported model formats
        val MODEL_EXTENSIONS = setOf(
            ".gguf", ".ggml", ".bin",           // GGML/GGUF formats
            ".mlmodel", ".mlmodelc", ".mlpackage", // CoreML formats
            ".onnx",                             // ONNX format
            ".tflite",                           // TensorFlow Lite
            ".pt", ".pth",                       // PyTorch
            ".safetensors"                       // SafeTensors
        )
    }

    /**
     * Get the root storage path for RunAnywhere
     * Platform-specific implementations will override this
     */
    override fun getModelStoragePath(): String {
        return getDocumentsDirectory() + "/$ROOT_FOLDER"
    }

    /**
     * Get model directory following iOS structure:
     * ~/Documents/RunAnywhere/Models/{framework}/{modelId}/
     */
    override fun getModelDirectory(framework: String, modelId: String): String {
        val modelsPath = "${getModelStoragePath()}/$MODELS_FOLDER"

        // Use framework-specific folder if framework is known
        return if (framework != "unknown") {
            "$modelsPath/$framework/$modelId"
        } else {
            // Fallback to direct model folder (legacy structure)
            "$modelsPath/$modelId"
        }
    }

    /**
     * Create directory if it doesn't exist
     */
    override fun createDirectory(path: String) {
        logger.debug("Creating directory: $path")
        createDirectoryPlatform(path)
    }

    /**
     * Check if file exists
     */
    override fun fileExists(path: String): Boolean {
        return fileExistsPlatform(path)
    }

    /**
     * Delete a file
     */
    override fun deleteFile(path: String): Boolean {
        logger.debug("Deleting file: $path")
        return deleteFilePlatform(path)
    }

    /**
     * Calculate file checksum (MD5 or SHA256)
     */
    override fun calculateChecksum(path: String): String {
        return calculateChecksumPlatform(path)
    }

    /**
     * Get resume data for a model download
     */
    override fun getResumeData(modelId: String): ByteArray? {
        val resumePath = "${getDownloadsDirectory()}/$modelId.resume"
        return if (fileExists(resumePath)) {
            readFilePlatform(resumePath)
        } else {
            null
        }
    }

    /**
     * Save resume data for a model download
     */
    override fun saveResumeData(modelId: String, data: ByteArray) {
        val resumePath = "${getDownloadsDirectory()}/$modelId.resume"
        writeFilePlatform(resumePath, data)
    }

    /**
     * Get available storage space
     */
    override fun getAvailableSpace(): Long {
        return getAvailableSpacePlatform()
    }

    /**
     * Get size of a directory
     */
    override fun getDirectorySize(path: String): Long {
        return getDirectorySizePlatform(path)
    }

    // Helper methods

    /**
     * Get cache directory
     */
    fun getCacheDirectory(): String {
        return "${getModelStoragePath()}/$CACHE_FOLDER"
    }

    /**
     * Get temp directory
     */
    fun getTempDirectory(): String {
        return "${getModelStoragePath()}/$TEMP_FOLDER"
    }

    /**
     * Get downloads directory
     */
    fun getDownloadsDirectory(): String {
        return "${getModelStoragePath()}/$DOWNLOADS_FOLDER"
    }

    /**
     * Detect existing models in storage
     * Matches iOS's detectExistingModels pattern
     */
    fun detectExistingModels(): List<DetectedModel> {
        val models = mutableListOf<DetectedModel>()
        val modelsPath = "${getModelStoragePath()}/$MODELS_FOLDER"

        if (!fileExists(modelsPath)) {
            return models
        }

        // Scan framework directories
        listDirectoriesPlatform(modelsPath).forEach { frameworkDir ->
            val frameworkPath = "$modelsPath/$frameworkDir"

            // Scan model directories within framework
            listDirectoriesPlatform(frameworkPath).forEach { modelDir ->
                val modelPath = "$frameworkPath/$modelDir"

                // Detect model files
                val modelFiles = findModelFiles(modelPath)
                if (modelFiles.isNotEmpty()) {
                    val totalSize = modelFiles.sumOf { getFileSizePlatform(it) }
                    models.add(
                        DetectedModel(
                            id = modelDir,
                            path = modelPath,
                            framework = frameworkDir,
                            format = detectModelFormat(modelFiles),
                            sizeBytes = totalSize,
                            files = modelFiles
                        )
                    )
                }
            }
        }

        // Also scan legacy direct model folders
        listDirectoriesPlatform(modelsPath).forEach { modelDir ->
            val modelPath = "$modelsPath/$modelDir"

            // Skip if it's a framework directory
            if (isFrameworkDirectory(modelDir)) {
                return@forEach
            }

            val modelFiles = findModelFiles(modelPath)
            if (modelFiles.isNotEmpty()) {
                val totalSize = modelFiles.sumOf { getFileSizePlatform(it) }
                models.add(
                    DetectedModel(
                        id = modelDir,
                        path = modelPath,
                        framework = "unknown",
                        format = detectModelFormat(modelFiles),
                        sizeBytes = totalSize,
                        files = modelFiles
                    )
                )
            }
        }

        logger.info("Detected ${models.size} existing models")
        return models
    }

    /**
     * Find model files in a directory
     */
    private fun findModelFiles(directory: String): List<String> {
        val modelFiles = mutableListOf<String>()

        listFilesPlatform(directory).forEach { file ->
            if (MODEL_EXTENSIONS.any { ext -> file.endsWith(ext) }) {
                modelFiles.add("$directory/$file")
            }
        }

        // Also check for .mlmodelc directories (CoreML compiled models)
        listDirectoriesPlatform(directory).forEach { dir ->
            if (dir.endsWith(".mlmodelc") || dir.endsWith(".mlpackage")) {
                modelFiles.add("$directory/$dir")
            }
        }

        return modelFiles
    }

    /**
     * Detect model format from files
     */
    private fun detectModelFormat(files: List<String>): String {
        return when {
            files.any { it.endsWith(".gguf") } -> "gguf"
            files.any { it.endsWith(".ggml") } -> "ggml"
            files.any { it.endsWith(".mlmodel") || it.endsWith(".mlmodelc") } -> "coreml"
            files.any { it.endsWith(".onnx") } -> "onnx"
            files.any { it.endsWith(".tflite") } -> "tflite"
            files.any { it.endsWith(".pt") || it.endsWith(".pth") } -> "pytorch"
            files.any { it.endsWith(".safetensors") } -> "safetensors"
            files.any { it.endsWith(".bin") } -> "binary"
            else -> "unknown"
        }
    }

    /**
     * Check if directory name is a framework directory
     */
    private fun isFrameworkDirectory(name: String): Boolean {
        val frameworks = setOf(
            "llamaCpp", "whisperKit", "whisperCpp", "coreML",
            "onnx", "tensorflowLite", "pytorch", "foundationModels"
        )
        return frameworks.contains(name)
    }

    /**
     * Clean up temporary files
     */
    fun cleanupTempFiles() {
        val tempDir = getTempDirectory()
        if (fileExists(tempDir)) {
            deleteDirectoryPlatform(tempDir)
            createDirectory(tempDir)
        }
    }

    /**
     * Initialize directory structure
     */
    fun initializeDirectoryStructure() {
        val directories = listOf(
            getModelStoragePath(),
            "${getModelStoragePath()}/$MODELS_FOLDER",
            getCacheDirectory(),
            getTempDirectory(),
            getDownloadsDirectory()
        )

        directories.forEach { dir ->
            if (!fileExists(dir)) {
                createDirectory(dir)
                logger.debug("Created directory: $dir")
            }
        }
    }

    // Platform-specific methods (to be implemented by actual platforms)

    /**
     * Get documents directory (platform-specific)
     */
    private fun getDocumentsDirectory(): String {
        // This will be overridden by platform-specific implementations
        return System.getProperty("user.home") ?: "."
    }

    // These will be implemented as expect/actual functions
    private external fun createDirectoryPlatform(path: String)
    private external fun fileExistsPlatform(path: String): Boolean
    private external fun deleteFilePlatform(path: String): Boolean
    private external fun deleteDirectoryPlatform(path: String): Boolean
    private external fun calculateChecksumPlatform(path: String): String
    private external fun readFilePlatform(path: String): ByteArray?
    private external fun writeFilePlatform(path: String, data: ByteArray)
    private external fun getAvailableSpacePlatform(): Long
    private external fun getDirectorySizePlatform(path: String): Long
    private external fun listDirectoriesPlatform(path: String): List<String>
    private external fun listFilesPlatform(path: String): List<String>
    private external fun getFileSizePlatform(path: String): Long
}

/**
 * Detected model information
 */
data class DetectedModel(
    val id: String,
    val path: String,
    val framework: String,
    val format: String,
    val sizeBytes: Long,
    val files: List<String>
)
