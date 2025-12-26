package com.runanywhere.sdk.foundation.filemanager

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.platform.getPlatformBaseDirectory
import com.runanywhere.sdk.platform.getPlatformStorageInfo
import com.runanywhere.sdk.platform.getPlatformTempDirectory
import kotlinx.coroutines.runBlocking
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * Simplified File Manager for SDK file operations
 * Matches iOS SimplifiedFileManager using Okio instead of Files library
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/FileSystem/SimplifiedFileManager.swift
 *
 * Key differences from iOS:
 * - iOS uses Files library (JohnSundell/Files)
 * - Kotlin uses Okio (Square/okio)
 * - Both provide elegant file system abstractions
 */
class SimplifiedFileManager {
    private val fileSystem: FileSystem = FileSystem.SYSTEM
    private val logger = SDKLogger.shared

    companion object {
        val shared = SimplifiedFileManager()
    }

    /**
     * Base directory for SDK files
     * Matches iOS baseDirectory (baseFolder) property
     */
    val baseDirectory: Path by lazy {
        getPlatformBaseDirectory().toPath()
    }

    /**
     * Temporary directory for SDK
     * Matches iOS temporaryDirectory property
     */
    val temporaryDirectory: Path by lazy {
        getPlatformTempDirectory().toPath()
    }

    /**
     * Models directory
     * Matches iOS modelsDirectory property
     */
    val modelsDirectory: Path by lazy {
        baseDirectory / "models"
    }

    /**
     * Cache directory
     * Matches iOS cacheDirectory property
     */
    val cacheDirectory: Path by lazy {
        baseDirectory / "cache"
    }

    /**
     * Database directory
     * Matches iOS databaseDirectory property
     */
    val databaseDirectory: Path by lazy {
        baseDirectory / "database"
    }

    /**
     * Logs directory
     * Matches iOS logsDirectory property
     */
    val logsDirectory: Path by lazy {
        baseDirectory / "logs"
    }

    /**
     * Downloads directory
     * Matches iOS Downloads folder
     */
    val downloadsDirectory: Path by lazy {
        baseDirectory / "downloads"
    }

    /**
     * Ensure all required directories exist
     * Matches iOS createDirectoryStructure() method
     */
    fun setupDirectories() {
        // Matches iOS directory structure: Models, Cache, Temp, Downloads
        val directories =
            listOf(
                baseDirectory,
                modelsDirectory,
                cacheDirectory,
                databaseDirectory,
                logsDirectory,
                temporaryDirectory,
                downloadsDirectory,
            )

        directories.forEach { dir ->
            try {
                if (!fileSystem.exists(dir)) {
                    fileSystem.createDirectories(dir)
                    logger.debug("Created directory: $dir")
                }
            } catch (e: Exception) {
                logger.error("Failed to create directory: $dir", e)
            }
        }
    }

    /**
     * Check if file exists
     * Matches iOS fileExists(at:) method
     */
    fun fileExists(path: String): Boolean = fileSystem.exists(path.toPath())

    /**
     * Check if path is a directory
     * Matches iOS isDirectory(at:) method
     */
    fun isDirectory(path: String): Boolean =
        try {
            val metadata = fileSystem.metadata(path.toPath())
            metadata.isDirectory
        } catch (e: Exception) {
            false
        }

    /**
     * Get file size
     * Matches iOS fileSize(at:) method
     */
    fun fileSize(path: String): Long? =
        try {
            val metadata = fileSystem.metadata(path.toPath())
            metadata.size
        } catch (e: Exception) {
            logger.error("Failed to get file size: $path", e)
            null
        }

    /**
     * Delete file
     * Matches iOS deleteFile(at:) method
     */
    fun deleteFile(path: String): Boolean =
        try {
            val filePath = path.toPath()
            if (fileSystem.exists(filePath)) {
                fileSystem.delete(filePath)
                logger.debug("Deleted file: $path")
                true
            } else {
                logger.warn("File does not exist: $path")
                false
            }
        } catch (e: Exception) {
            logger.error("Failed to delete file: $path", e)
            false
        }

    /**
     * Delete directory recursively
     * Matches iOS deleteDirectory(at:) method
     */
    fun deleteDirectory(path: String): Boolean =
        try {
            val dirPath = path.toPath()
            if (fileSystem.exists(dirPath)) {
                fileSystem.deleteRecursively(dirPath)
                logger.debug("Deleted directory: $path")
                true
            } else {
                logger.warn("Directory does not exist: $path")
                false
            }
        } catch (e: Exception) {
            logger.error("Failed to delete directory: $path", e)
            false
        }

    /**
     * Calculate directory size
     * Matches iOS directorySize(at:) method
     */
    fun directorySize(path: String): Long {
        var totalSize = 0L
        try {
            val dirPath = path.toPath()
            if (fileSystem.exists(dirPath)) {
                listFilesRecursively(dirPath).forEach { filePath ->
                    val metadata = fileSystem.metadata(filePath)
                    if (metadata.isRegularFile) {
                        totalSize += metadata.size ?: 0L
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to calculate directory size: $path", e)
        }
        return totalSize
    }

    /**
     * List files in directory (non-recursive)
     * Matches iOS listFiles(at:) method
     */
    fun listFiles(path: String): List<String> =
        try {
            val dirPath = path.toPath()
            if (fileSystem.exists(dirPath)) {
                fileSystem.list(dirPath).map { it.toString() }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            logger.error("Failed to list files: $path", e)
            emptyList()
        }

    /**
     * List files recursively
     * Matches iOS listFilesRecursively(at:) method
     */
    private fun listFilesRecursively(path: Path): List<Path> {
        val files = mutableListOf<Path>()
        try {
            if (fileSystem.exists(path)) {
                val metadata = fileSystem.metadata(path)
                if (metadata.isDirectory) {
                    fileSystem.list(path).forEach { childPath ->
                        val childMetadata = fileSystem.metadata(childPath)
                        if (childMetadata.isRegularFile) {
                            files.add(childPath)
                        } else if (childMetadata.isDirectory) {
                            files.addAll(listFilesRecursively(childPath))
                        }
                    }
                } else if (metadata.isRegularFile) {
                    files.add(path)
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to list files recursively: $path", e)
        }
        return files
    }

    /**
     * Create directory
     * Matches iOS createDirectory(at:) method
     */
    fun createDirectory(path: String): Boolean =
        try {
            val dirPath = path.toPath()
            if (!fileSystem.exists(dirPath)) {
                fileSystem.createDirectories(dirPath)
                logger.debug("Created directory: $path")
            }
            true
        } catch (e: Exception) {
            logger.error("Failed to create directory: $path", e)
            false
        }

    /**
     * Move file
     * Matches iOS moveFile(from:to:) method
     */
    fun moveFile(
        from: String,
        to: String,
    ): Boolean =
        try {
            val fromPath = from.toPath()
            val toPath = to.toPath()
            fileSystem.atomicMove(fromPath, toPath)
            logger.debug("Moved file: $from -> $to")
            true
        } catch (e: Exception) {
            logger.error("Failed to move file: $from -> $to", e)
            false
        }

    /**
     * Copy file
     * Matches iOS copyFile(from:to:) method
     */
    fun copyFile(
        from: String,
        to: String,
    ): Boolean =
        try {
            val fromPath = from.toPath()
            val toPath = to.toPath()
            fileSystem.copy(fromPath, toPath)
            logger.debug("Copied file: $from -> $to")
            true
        } catch (e: Exception) {
            logger.error("Failed to copy file: $from -> $to", e)
            false
        }

    // MARK: - Storage Information
    // Matches iOS SimplifiedFileManager storage methods exactly

    /**
     * Get total storage size
     * Matches iOS getTotalStorageSize() method exactly
     *
     * Calculates size recursively for all files in base folder
     */
    fun getTotalStorageSize(): Long = directorySize(baseDirectory.toString())

    /**
     * Get model storage size
     * Matches iOS getModelStorageSize() method exactly
     */
    fun getModelStorageSize(): Long =
        if (fileSystem.exists(modelsDirectory)) {
            directorySize(modelsDirectory.toString())
        } else {
            0L
        }

    /**
     * Calculate the total size of a directory including all subdirectories and files
     * Matches iOS calculateDirectorySize(at:) method exactly
     *
     * Uses FileManager.enumerator pattern from iOS:
     * ```swift
     * if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
     *     for case let fileURL as URL in enumerator {
     *         if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
     *             totalSize += Int64(fileSize)
     *         }
     *     }
     * }
     * ```
     */
    fun calculateDirectorySize(path: String): Long = directorySize(path)

    /**
     * Get available space
     * Matches iOS getAvailableSpace() method exactly
     *
     * iOS implementation:
     * ```swift
     * let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
     * return values.volumeAvailableCapacityForImportantUsage ?? 0
     * ```
     */
    fun getAvailableSpace(): Long =
        runBlocking {
            try {
                val storageInfo = getPlatformStorageInfo(baseDirectory.toString())
                storageInfo.availableSpace
            } catch (e: Exception) {
                logger.error("Failed to get available space", e)
                0L
            }
        }

    /**
     * Get device storage information (total, free, used space)
     * Matches iOS getDeviceStorageInfo() method exactly
     *
     * iOS implementation:
     * ```swift
     * let attributes = try FileManager.default.attributesOfFileSystem(forPath: homeURL.path)
     * let totalSpace = (attributes[.systemSize] as? Int64) ?? 0
     * let freeSpace = (attributes[.systemFreeSize] as? Int64) ?? 0
     * let usedSpace = totalSpace - freeSpace
     * return (totalSpace: totalSpace, freeSpace: freeSpace, usedSpace: usedSpace)
     * ```
     */
    fun getDeviceStorageInfo(): DeviceStorageData =
        runBlocking {
            try {
                val storageInfo = getPlatformStorageInfo(baseDirectory.toString())
                DeviceStorageData(
                    totalSpace = storageInfo.totalSpace,
                    freeSpace = storageInfo.availableSpace,
                    usedSpace = storageInfo.usedSpace,
                )
            } catch (e: Exception) {
                logger.error("Failed to get device storage info", e)
                DeviceStorageData(0L, 0L, 0L)
            }
        }

    /**
     * Get all stored models
     * Matches iOS getAllStoredModels() method exactly
     *
     * Returns: List of (modelId, format, size, framework)
     *
     * iOS scans:
     * 1. Direct model folders (legacy structure)
     * 2. Framework-specific folders (e.g., llama_cpp/, onnx/)
     */
    fun getAllStoredModels(): List<StoredModelData> {
        val models = mutableListOf<StoredModelData>()

        if (!fileSystem.exists(modelsDirectory)) {
            return models
        }

        try {
            val modelsPath = modelsDirectory.toString()
            val entries = listFiles(modelsPath)

            for (entryPath in entries) {
                val entryName = entryPath.substringAfterLast("/")

                // Check if this is a framework folder
                val framework =
                    InferenceFramework.values().firstOrNull {
                        it.value.equals(entryName, ignoreCase = true) ||
                            it.displayName.equals(entryName, ignoreCase = true)
                    }

                if (framework != null) {
                    // Scan framework-specific folder
                    val frameworkModels = scanFrameworkFolder(entryPath, framework)
                    models.addAll(frameworkModels)
                } else if (isDirectory(entryPath)) {
                    // Direct model folder (legacy structure)
                    val modelInfo = detectModelInFolder(entryPath)
                    if (modelInfo != null) {
                        models.add(
                            StoredModelData(
                                modelId = entryName,
                                format = modelInfo.format,
                                size = modelInfo.size,
                                framework = null,
                            ),
                        )
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to get all stored models", e)
        }

        return models
    }

    /**
     * Scan framework-specific folder for models
     * Matches iOS getAllStoredModels() framework scanning logic
     */
    private fun scanFrameworkFolder(
        frameworkPath: String,
        framework: InferenceFramework,
    ): List<StoredModelData> {
        val models = mutableListOf<StoredModelData>()

        try {
            val modelFolders = listFiles(frameworkPath)

            for (modelFolderPath in modelFolders) {
                if (!isDirectory(modelFolderPath)) continue

                val modelId = modelFolderPath.substringAfterLast("/")
                val modelInfo = detectModelInFolder(modelFolderPath)

                if (modelInfo != null) {
                    models.add(
                        StoredModelData(
                            modelId = modelId,
                            format = modelInfo.format,
                            size = modelInfo.size,
                            framework = framework,
                        ),
                    )
                    logger.debug("Detected ${framework.value} model $modelId: ${modelInfo.size} bytes")
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to scan framework folder: $frameworkPath", e)
        }

        return models
    }

    /**
     * Detect model format and size in a folder
     * Matches iOS detectModelInFolder() method exactly
     *
     * iOS implementation:
     * ```swift
     * // Check for single model files
     * for file in folder.files {
     *     if let format = ModelFormat(rawValue: file.extension ?? "") {
     *         var fileSize: Int64 = 0
     *         if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
     *            let size = attributes[.size] as? NSNumber {
     *             fileSize = size.int64Value
     *         }
     *         return (format, fileSize)
     *     }
     * }
     * // If no single model file, calculate total directory size
     * let totalSize = calculateDirectorySize(at: URL(fileURLWithPath: folder.path))
     * if totalSize > 0 {
     *     return (.mlmodel, totalSize)
     * }
     * ```
     */
    private fun detectModelInFolder(folderPath: String): ModelDetection? {
        try {
            val files = listFiles(folderPath)

            // First, check for single model files (GGUF, ONNX)
            for (filePath in files) {
                if (isDirectory(filePath)) continue

                val fileName = filePath.substringAfterLast("/")
                val extension = fileName.substringAfterLast(".", "").lowercase()

                val format =
                    when (extension) {
                        "gguf" -> ModelFormat.GGUF
                        "onnx" -> ModelFormat.ONNX
                        "mlmodel", "mlmodelc" -> ModelFormat.MLMODEL
                        "mlpackage" -> ModelFormat.MLPACKAGE
                        "tflite" -> ModelFormat.TFLITE
                        "safetensors" -> ModelFormat.MLX
                        else -> null
                    }

                if (format != null) {
                    val fileSize = fileSize(filePath) ?: 0L
                    return ModelDetection(format, fileSize)
                }
            }

            // Check for ONNX directory structure (sherpa-onnx models)
            // These have multiple .onnx files (encoder, decoder) and tokens.txt
            val hasOnnxFiles = files.any { !isDirectory(it) && it.endsWith(".onnx", ignoreCase = true) }

            if (hasOnnxFiles) {
                val totalSize = directorySize(folderPath)
                return ModelDetection(ModelFormat.ONNX, totalSize)
            }

            // Check subdirectories for nested ONNX models (sherpa-onnx structure)
            for (filePath in files) {
                if (isDirectory(filePath)) {
                    val subFiles = listFiles(filePath)
                    val subHasOnnx = subFiles.any { !isDirectory(it) && it.endsWith(".onnx", ignoreCase = true) }
                    if (subHasOnnx) {
                        val totalSize = directorySize(folderPath)
                        return ModelDetection(ModelFormat.ONNX, totalSize)
                    }
                }
            }

            // If no single model file, calculate total directory size
            // Return as ONNX format for directory-based models (matches iOS .mlmodel default)
            val totalSize = directorySize(folderPath)
            if (totalSize > 0) {
                return ModelDetection(ModelFormat.ONNX, totalSize)
            }
        } catch (e: Exception) {
            logger.error("Failed to detect model in folder: $folderPath", e)
        }

        return null
    }

    /**
     * Delete model
     * Matches iOS deleteModel(modelId:) method exactly
     *
     * Searches in framework-specific folders first, then direct model folders (legacy)
     */
    fun deleteModel(modelId: String): Boolean {
        try {
            val modelsPath = modelsDirectory.toString()

            // Check framework-specific folders first
            for (framework in InferenceFramework.values()) {
                val frameworkPath = "$modelsPath/${framework.value}"
                if (fileSystem.exists(frameworkPath.toPath())) {
                    val modelPath = "$frameworkPath/$modelId"
                    if (fileSystem.exists(modelPath.toPath())) {
                        deleteDirectory(modelPath)
                        logger.info("Deleted model: $modelId from framework: ${framework.value}")
                        return true
                    }
                }
            }

            // Check direct model folder (legacy)
            val directPath = "$modelsPath/$modelId"
            if (fileSystem.exists(directPath.toPath())) {
                deleteDirectory(directPath)
                logger.info("Deleted model: $modelId")
                return true
            }

            logger.warn("Model not found for deletion: $modelId")
            return false
        } catch (e: Exception) {
            logger.error("Failed to delete model: $modelId", e)
            return false
        }
    }

    /**
     * Find model file by searching all possible locations
     * Matches iOS findModelFile(modelId:expectedPath:) method exactly
     */
    fun findModelFile(
        modelId: String,
        expectedPath: String? = null,
    ): String? {
        // If expected path exists and is valid, return it
        if (expectedPath != null && fileExists(expectedPath)) {
            return expectedPath
        }

        if (!fileSystem.exists(modelsDirectory)) return null

        try {
            val modelsPath = modelsDirectory.toString()

            // Search in framework-specific folders first
            for (framework in InferenceFramework.values()) {
                val frameworkPath = "$modelsPath/${framework.value}"
                if (!fileSystem.exists(frameworkPath.toPath())) continue

                val modelFolderPath = "$frameworkPath/$modelId"
                if (fileSystem.exists(modelFolderPath.toPath())) {
                    // Search for model files in the folder
                    val files = listFiles(modelFolderPath)
                    for (filePath in files) {
                        if (!isDirectory(filePath)) {
                            val extension = filePath.substringAfterLast(".", "").lowercase()
                            if (extension in listOf("gguf", "onnx", "mlmodel", "mlmodelc", "tflite", "safetensors")) {
                                logger.info("Found model $modelId at: $filePath")
                                return filePath
                            }
                        }
                    }

                    // Check if it's a directory-based model (ONNX)
                    val modelInfo = detectModelInFolder(modelFolderPath)
                    if (modelInfo != null) {
                        logger.info("Found directory-based model $modelId at: $modelFolderPath")
                        return modelFolderPath
                    }
                }
            }

            // Search in direct model folders (legacy)
            val directPath = "$modelsPath/$modelId"
            if (fileSystem.exists(directPath.toPath())) {
                val files = listFiles(directPath)
                for (filePath in files) {
                    if (!isDirectory(filePath)) {
                        val extension = filePath.substringAfterLast(".", "").lowercase()
                        if (extension in listOf("gguf", "onnx", "mlmodel", "mlmodelc", "tflite", "safetensors")) {
                            logger.info("Found model $modelId at: $filePath")
                            return filePath
                        }
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to find model file: $modelId", e)
        }

        logger.warn("Model file not found for: $modelId")
        return null
    }

    /**
     * Clear all cache
     * Matches iOS clearCache() method exactly
     */
    fun clearCache(): Boolean =
        try {
            if (fileSystem.exists(cacheDirectory)) {
                val files = listFiles(cacheDirectory.toString())
                files.forEach { deleteFile(it) }
                logger.info("Cleared all cache")
            }
            true
        } catch (e: Exception) {
            logger.error("Failed to clear cache", e)
            false
        }

    /**
     * Clean temporary files
     * Matches iOS cleanTempFiles() method exactly
     */
    fun cleanTempFiles(): Boolean =
        try {
            if (fileSystem.exists(temporaryDirectory)) {
                val files = listFiles(temporaryDirectory.toString())
                files.forEach { filePath ->
                    if (isDirectory(filePath)) {
                        deleteDirectory(filePath)
                    } else {
                        deleteFile(filePath)
                    }
                }
                logger.info("Cleaned temporary files")
            }
            true
        } catch (e: Exception) {
            logger.error("Failed to clean temp files", e)
            false
        }

    /**
     * Get base directory URL (as string path)
     * Matches iOS getBaseDirectoryURL() method
     */
    fun getBaseDirectoryURL(): String = baseDirectory.toString()
}

/**
 * Data class for device storage information
 * Matches iOS (totalSpace, freeSpace, usedSpace) tuple
 */
data class DeviceStorageData(
    val totalSpace: Long,
    val freeSpace: Long,
    val usedSpace: Long,
)

/**
 * Data class for stored model information
 * Matches iOS (modelId, format, size, framework) tuple
 */
data class StoredModelData(
    val modelId: String,
    val format: ModelFormat,
    val size: Long,
    val framework: InferenceFramework?,
)

/**
 * Data class for model detection result
 * Matches iOS (format: ModelFormat, size: Int64) tuple
 */
data class ModelDetection(
    val format: ModelFormat,
    val size: Long,
)
