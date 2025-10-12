package com.runanywhere.sdk.foundation.filemanager

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.platform.getPlatformBaseDirectory
import com.runanywhere.sdk.platform.getPlatformTempDirectory
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * Simplified File Manager for SDK file operations
 * Matches iOS SimplifiedFileManager using Okio instead of Files library
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/FileSystem/SimplifiedFileManager.swift
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
     * Matches iOS baseDirectory property
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
     * Ensure all required directories exist
     * Matches iOS setupDirectories() method
     */
    fun setupDirectories() {
        val directories = listOf(
            baseDirectory,
            modelsDirectory,
            cacheDirectory,
            databaseDirectory,
            logsDirectory,
            temporaryDirectory
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
    fun fileExists(path: String): Boolean {
        return fileSystem.exists(path.toPath())
    }

    /**
     * Get file size
     * Matches iOS fileSize(at:) method
     */
    fun fileSize(path: String): Long? {
        return try {
            val metadata = fileSystem.metadata(path.toPath())
            metadata.size
        } catch (e: Exception) {
            logger.error("Failed to get file size: $path", e)
            null
        }
    }

    /**
     * Delete file
     * Matches iOS deleteFile(at:) method
     */
    fun deleteFile(path: String): Boolean {
        return try {
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
    }

    /**
     * Delete directory recursively
     * Matches iOS deleteDirectory(at:) method
     */
    fun deleteDirectory(path: String): Boolean {
        return try {
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
    fun listFiles(path: String): List<String> {
        return try {
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
    fun createDirectory(path: String): Boolean {
        return try {
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
    }

    /**
     * Move file
     * Matches iOS moveFile(from:to:) method
     */
    fun moveFile(from: String, to: String): Boolean {
        return try {
            val fromPath = from.toPath()
            val toPath = to.toPath()
            fileSystem.atomicMove(fromPath, toPath)
            logger.debug("Moved file: $from -> $to")
            true
        } catch (e: Exception) {
            logger.error("Failed to move file: $from -> $to", e)
            false
        }
    }

    /**
     * Copy file
     * Matches iOS copyFile(from:to:) method
     */
    fun copyFile(from: String, to: String): Boolean {
        return try {
            val fromPath = from.toPath()
            val toPath = to.toPath()
            fileSystem.copy(fromPath, toPath)
            logger.debug("Copied file: $from -> $to")
            true
        } catch (e: Exception) {
            logger.error("Failed to copy file: $from -> $to", e)
            false
        }
    }
}
