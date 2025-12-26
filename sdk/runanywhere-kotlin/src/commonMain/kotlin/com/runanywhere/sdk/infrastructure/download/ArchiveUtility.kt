package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.ArchiveType

/**
 * Utility for handling archive operations
 * Matches iOS ArchiveUtility interface exactly
 *
 * Supports:
 * - tar.bz2 (using platform-specific implementations)
 * - tar.gz (using platform-specific implementations)
 * - tar.xz (using platform-specific implementations)
 * - zip (using platform-specific implementations)
 *
 * @see com.runanywhere.sdk.models.enums.ArchiveType
 */
object ArchiveUtility {
    private val logger = SDKLogger("ArchiveUtility")

    /**
     * Supported archive formats
     * Matches iOS ArchiveUtility.ArchiveFormat
     */
    enum class ArchiveFormat {
        TAR_BZ2,
        TAR_GZ,
        TAR_XZ,
        ZIP,
        UNKNOWN,
    }

    /**
     * Extract any supported archive format based on file extension
     * Matches iOS extractArchive(from:to:progressHandler:)
     *
     * @param sourcePath Path to the archive file
     * @param destinationPath Destination directory path
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @throws ArchiveExtractionException if extraction fails or format is unsupported
     */
    suspend fun extractArchive(
        sourcePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null,
    ) {
        val archiveType = detectArchiveType(sourcePath)

        when (archiveType) {
            ArchiveFormat.TAR_BZ2 -> extractTarBz2Archive(sourcePath, destinationPath, progressHandler)
            ArchiveFormat.TAR_GZ -> extractTarGzArchive(sourcePath, destinationPath, progressHandler)
            ArchiveFormat.TAR_XZ -> extractTarXzArchive(sourcePath, destinationPath, progressHandler)
            ArchiveFormat.ZIP -> extractZipArchive(sourcePath, destinationPath, progressHandler)
            ArchiveFormat.UNKNOWN -> throw ArchiveExtractionException("Unsupported archive format: $sourcePath")
        }
    }

    /**
     * Extract a tar.bz2 archive to a destination directory
     * Matches iOS extractTarBz2Archive(from:to:progressHandler:)
     *
     * @param sourcePath Path to the tar.bz2 file
     * @param destinationPath Destination directory path
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @throws ArchiveExtractionException if extraction fails
     */
    suspend fun extractTarBz2Archive(
        sourcePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null,
    ) {
        logger.info("Extracting tar.bz2 archive: $sourcePath")
        progressHandler?.invoke(0.0)

        try {
            extractTarBz2Impl(sourcePath, destinationPath, progressHandler)
            logger.info("tar.bz2 extraction completed to: $destinationPath")
            progressHandler?.invoke(1.0)
        } catch (e: Exception) {
            logger.error("BZip2 extraction failed: ${e.message}")
            throw ArchiveExtractionException("BZip2 extraction failed: ${e.message}", e)
        }
    }

    /**
     * Extract a tar.gz archive to a destination directory
     * Matches iOS extractTarGzArchive(from:to:progressHandler:)
     *
     * @param sourcePath Path to the tar.gz file
     * @param destinationPath Destination directory path
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @throws ArchiveExtractionException if extraction fails
     */
    suspend fun extractTarGzArchive(
        sourcePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null,
    ) {
        logger.info("Extracting tar.gz archive: $sourcePath")
        progressHandler?.invoke(0.0)

        try {
            extractTarGzImpl(sourcePath, destinationPath, progressHandler)
            logger.info("tar.gz extraction completed to: $destinationPath")
            progressHandler?.invoke(1.0)
        } catch (e: Exception) {
            logger.error("Gzip extraction failed: ${e.message}")
            throw ArchiveExtractionException("Gzip extraction failed: ${e.message}", e)
        }
    }

    /**
     * Extract a tar.xz archive to a destination directory
     * Matches iOS extractTarXzArchive(from:to:progressHandler:)
     *
     * @param sourcePath Path to the tar.xz file
     * @param destinationPath Destination directory path
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @throws ArchiveExtractionException if extraction fails
     */
    suspend fun extractTarXzArchive(
        sourcePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null,
    ) {
        logger.info("Extracting tar.xz archive: $sourcePath")
        progressHandler?.invoke(0.0)

        try {
            extractTarXzImpl(sourcePath, destinationPath, progressHandler)
            logger.info("tar.xz extraction completed to: $destinationPath")
            progressHandler?.invoke(1.0)
        } catch (e: Exception) {
            logger.error("XZ extraction failed: ${e.message}")
            throw ArchiveExtractionException("XZ extraction failed: ${e.message}", e)
        }
    }

    /**
     * Extract a zip archive to a destination directory
     * Matches iOS extractZipArchive(from:to:progressHandler:)
     *
     * @param sourcePath Path to the zip file
     * @param destinationPath Destination directory path
     * @param progressHandler Optional callback for extraction progress (0.0 to 1.0)
     * @throws ArchiveExtractionException if extraction fails
     */
    suspend fun extractZipArchive(
        sourcePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null,
    ) {
        logger.info("Extracting zip archive: $sourcePath")
        progressHandler?.invoke(0.0)

        try {
            extractZipImpl(sourcePath, destinationPath, progressHandler)
            logger.info("zip extraction completed to: $destinationPath")
            progressHandler?.invoke(1.0)
        } catch (e: Exception) {
            logger.error("Zip extraction failed: ${e.message}")
            throw ArchiveExtractionException("Zip extraction failed: ${e.message}", e)
        }
    }

    /**
     * Detect archive type from file path
     * Matches iOS detectArchiveType(from:)
     *
     * @param path File path to check
     * @return Detected archive format
     */
    fun detectArchiveType(path: String): ArchiveFormat {
        val lowercasedPath = path.lowercase()

        return when {
            lowercasedPath.endsWith(".tar.bz2") ||
                lowercasedPath.endsWith(".tbz2") ||
                lowercasedPath.endsWith(".tbz") -> ArchiveFormat.TAR_BZ2

            lowercasedPath.endsWith(".tar.gz") ||
                lowercasedPath.endsWith(".tgz") -> ArchiveFormat.TAR_GZ

            lowercasedPath.endsWith(".tar.xz") ||
                lowercasedPath.endsWith(".txz") -> ArchiveFormat.TAR_XZ

            lowercasedPath.endsWith(".zip") -> ArchiveFormat.ZIP

            else -> ArchiveFormat.UNKNOWN
        }
    }

    /**
     * Convert from ArchiveType enum to ArchiveFormat
     */
    fun fromArchiveType(archiveType: ArchiveType): ArchiveFormat {
        return when (archiveType) {
            ArchiveType.TAR_BZ2 -> ArchiveFormat.TAR_BZ2
            ArchiveType.TAR_GZ -> ArchiveFormat.TAR_GZ
            ArchiveType.TAR_XZ -> ArchiveFormat.TAR_XZ
            ArchiveType.ZIP -> ArchiveFormat.ZIP
        }
    }

    /**
     * Check if a path points to a tar.bz2 archive
     * Matches iOS isTarBz2Archive(_:)
     */
    fun isTarBz2Archive(path: String): Boolean = detectArchiveType(path) == ArchiveFormat.TAR_BZ2

    /**
     * Check if a path points to a tar.gz archive
     * Matches iOS isTarGzArchive(_:)
     */
    fun isTarGzArchive(path: String): Boolean = detectArchiveType(path) == ArchiveFormat.TAR_GZ

    /**
     * Check if a path points to a tar.xz archive
     */
    fun isTarXzArchive(path: String): Boolean = detectArchiveType(path) == ArchiveFormat.TAR_XZ

    /**
     * Check if a path points to a zip archive
     * Matches iOS isZipArchive(_:)
     */
    fun isZipArchive(path: String): Boolean = detectArchiveType(path) == ArchiveFormat.ZIP

    /**
     * Check if a path points to any supported archive format
     * Matches iOS isSupportedArchive(_:)
     */
    fun isSupportedArchive(path: String): Boolean = detectArchiveType(path) != ArchiveFormat.UNKNOWN

    /**
     * Format bytes for logging
     * Matches iOS formatBytes(_:)
     */
    fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format("%.1f KB", bytes.toDouble() / 1024)
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes.toDouble() / (1024 * 1024))
            else -> String.format("%.2f GB", bytes.toDouble() / (1024 * 1024 * 1024))
        }
    }
}

/**
 * Exception thrown when archive extraction fails
 * Matches iOS DownloadError.extractionFailed
 */
class ArchiveExtractionException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

// Platform-specific extraction implementations
internal expect suspend fun extractTarBz2Impl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
)

internal expect suspend fun extractTarGzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
)

internal expect suspend fun extractTarXzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
)

internal expect suspend fun extractZipImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
)
