package com.runanywhere.sdk.infrastructure.modelmanagement.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.download.ArchiveExtractionException
import com.runanywhere.sdk.infrastructure.download.ArchiveUtility
import com.runanywhere.sdk.models.enums.ArchiveStructure
import com.runanywhere.sdk.models.enums.ArchiveType
import com.runanywhere.sdk.models.enums.ModelArtifactType

/**
 * Result of an extraction operation
 * Matches iOS ExtractionResult exactly
 */
data class ExtractionResult(
    /**
     * Path to the extracted model (could be file or directory)
     */
    val modelPath: String,
    /**
     * Total extracted size in bytes
     */
    val extractedSize: Long,
    /**
     * Number of files extracted
     */
    val fileCount: Int,
    /**
     * Duration of extraction in seconds
     */
    val durationSeconds: Double,
)

/**
 * Protocol for model extraction service
 * Matches iOS ModelExtractionServiceProtocol exactly
 */
interface ModelExtractionServiceProtocol {
    /**
     * Extract an archive based on the model's artifact type
     *
     * @param archivePath Path to the downloaded archive
     * @param destinationPath Directory to extract to
     * @param artifactType The model's artifact type (determines extraction method)
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @return Result containing the path to the extracted model
     * @throws ArchiveExtractionException if extraction fails
     */
    suspend fun extract(
        archivePath: String,
        destinationPath: String,
        artifactType: ModelArtifactType,
        progressHandler: ((Double) -> Unit)? = null,
    ): ExtractionResult
}

/**
 * Default implementation of the model extraction service
 * Uses ArchiveUtility for archive extraction
 * Matches iOS DefaultModelExtractionService exactly
 */
class DefaultModelExtractionService : ModelExtractionServiceProtocol {
    private val logger = SDKLogger("ModelExtractionService")

    override suspend fun extract(
        archivePath: String,
        destinationPath: String,
        artifactType: ModelArtifactType,
        progressHandler: ((Double) -> Unit)?,
    ): ExtractionResult {
        val startTime = currentTimeMillis()

        // Verify this is an archive type
        val archive =
            artifactType as? ModelArtifactType.Archive
                ?: throw ArchiveExtractionException("Artifact type does not require extraction: $artifactType")

        val archiveType = archive.archiveType
        val structure = archive.structure

        logger.info("Starting extraction: archivePath=$archivePath, destination=$destinationPath, archiveType=${archiveType.name}")

        // Ensure destination exists
        createDirectoryIfNeeded(destinationPath)

        // Report starting
        progressHandler?.invoke(0.0)

        // Perform extraction based on archive type
        when (archiveType) {
            ArchiveType.ZIP -> ArchiveUtility.extractZipArchive(archivePath, destinationPath, progressHandler)
            ArchiveType.TAR_BZ2 -> ArchiveUtility.extractTarBz2Archive(archivePath, destinationPath, progressHandler)
            ArchiveType.TAR_GZ -> ArchiveUtility.extractTarGzArchive(archivePath, destinationPath, progressHandler)
            ArchiveType.TAR_XZ -> ArchiveUtility.extractTarXzArchive(archivePath, destinationPath, progressHandler)
        }

        // Find the actual model path based on structure
        val modelPath = findModelPath(destinationPath, structure)

        // Calculate extracted size and file count
        val stats = calculateExtractionStats(destinationPath)

        val duration = (currentTimeMillis() - startTime) / 1000.0

        logger.info("Extraction completed: modelPath=$modelPath, extractedSize=${stats.first}, fileCount=${stats.second}, durationSeconds=$duration")

        progressHandler?.invoke(1.0)

        return ExtractionResult(
            modelPath = modelPath,
            extractedSize = stats.first,
            fileCount = stats.second,
            durationSeconds = duration,
        )
    }

    /**
     * Find the actual model path based on archive structure
     * Matches iOS findModelPath(in:structure:)
     */
    private fun findModelPath(extractedDir: String, structure: ArchiveStructure): String {
        return when (structure) {
            ArchiveStructure.SINGLE_FILE_NESTED -> {
                // Look for a single model file, possibly in a subdirectory
                findSingleModelFile(extractedDir) ?: extractedDir
            }

            ArchiveStructure.NESTED_DIRECTORY -> {
                // Common pattern: archive contains one subdirectory with all the files
                findNestedDirectory(extractedDir)
            }

            ArchiveStructure.DIRECTORY_BASED, ArchiveStructure.UNKNOWN -> {
                // Return the extraction directory itself
                extractedDir
            }
        }
    }

    /**
     * Find nested directory (for archives that extract to a subdirectory)
     * Matches iOS findNestedDirectory(in:)
     */
    private fun findNestedDirectory(extractedDir: String): String {
        val contents = listDirectoryContents(extractedDir) ?: return extractedDir

        // Filter out hidden files and macOS resource forks
        val visibleContents =
            contents.filter { name ->
                !name.startsWith(".") && !name.startsWith("._")
            }

        // If there's a single visible subdirectory, return it
        if (visibleContents.size == 1) {
            val first = visibleContents.first()
            val fullPath = "$extractedDir/$first"
            if (isDirectoryPath(fullPath)) {
                return fullPath
            }
        }

        return extractedDir
    }

    /**
     * Find a single model file in a directory (recursive, up to 2 levels)
     * Matches iOS findSingleModelFile(in:depth:)
     */
    private fun findSingleModelFile(directory: String, depth: Int = 0): String? {
        if (depth >= 2) return null

        val contents = listDirectoryContents(directory) ?: return null

        // Known model file extensions
        val modelExtensions = setOf("gguf", "ggml", "onnx", "mlmodel", "mlpackage", "tflite", "pte", "safetensors")

        // Look for model files at this level
        for (item in contents) {
            val extension = item.substringAfterLast('.', "").lowercase()
            if (extension in modelExtensions) {
                return "$directory/$item"
            }
        }

        // Recursively check subdirectories
        for (item in contents) {
            val fullPath = "$directory/$item"
            if (isDirectoryPath(fullPath)) {
                val found = findSingleModelFile(fullPath, depth + 1)
                if (found != null) {
                    return found
                }
            }
        }

        return null
    }

    /**
     * Calculate size and file count for extracted content
     * Matches iOS calculateExtractionStats(at:)
     */
    private fun calculateExtractionStats(directory: String): Pair<Long, Int> {
        return calculateDirectorySize(directory)
    }

    companion object {
        /**
         * Singleton instance for convenience
         */
        val shared = DefaultModelExtractionService()
    }
}

// Platform-specific helper functions (expect declarations)

/**
 * Get current time in milliseconds
 */
internal expect fun currentTimeMillis(): Long

/**
 * Create a directory if it doesn't exist
 */
internal expect fun createDirectoryIfNeeded(path: String)

/**
 * List contents of a directory
 * @return List of file/directory names, or null if the path is not a directory
 */
internal expect fun listDirectoryContents(path: String): List<String>?

/**
 * Check if a path is a directory
 */
internal expect fun isDirectoryPath(path: String): Boolean

/**
 * Calculate total size and file count for a directory
 * @return Pair of (totalBytes, fileCount)
 */
internal expect fun calculateDirectorySize(directory: String): Pair<Long, Int>
