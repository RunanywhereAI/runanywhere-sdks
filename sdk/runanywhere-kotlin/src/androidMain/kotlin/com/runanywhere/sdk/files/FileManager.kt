package com.runanywhere.sdk.files

import android.content.Context
import android.os.Environment
import android.os.StatFs
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.Date

actual fun calculateSHA256(data: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val hash = digest.digest(data)
    return hash.joinToString("") { "%02x".format(it) }
}

/**
 * File Manager
 * One-to-one translation from iOS FileManager to Android with thread-safety
 * Handles file operations, storage management, and cleanup
 */
actual class FileManager {

    private val logger = SDKLogger("FileManager")
    private val mutex = Mutex()
    private lateinit var context: Context

    // Directory structure matching iOS patterns
    private val baseDir by lazy { File(context.filesDir, "runanywhere") }
    private val modelsDir by lazy { File(baseDir, "models") }
    private val cacheDir by lazy { File(baseDir, "cache") }
    private val tempDir by lazy { File(baseDir, "temp") }
    private val logsDir by lazy { File(baseDir, "logs") }
    private val databaseDir by lazy { File(baseDir, "database") }

    fun setContext(appContext: Context) {
        context = appContext
        // Ensure directory structure exists
        createDirectoryStructure()
    }

    /**
     * Get model file path
     * Equivalent to iOS FileManager model path methods
     */
    actual fun getModelPath(modelId: String): String =
        File(modelsDir, "$modelId.bin").absolutePath

    /**
     * Get cache file path
     * Equivalent to iOS FileManager cache path methods
     */
    actual fun getCachePath(fileName: String): String {
        val safeKey = fileName.hashCode().toString()
        return File(cacheDir, safeKey).absolutePath
    }

    actual fun getTempPath(fileName: String): String {
        return File(tempDir, fileName).absolutePath
    }

    /**
     * Create temporary file
     * Equivalent to iOS FileManager temporary file creation
     */
    suspend fun createTempFile(prefix: String, suffix: String): File = mutex.withLock {
        logger.debug("Creating temporary file: $prefix*$suffix")

        try {
            ensureDirectoryExists(tempDir)
            val tempFile = File(tempDir, "${prefix}_${System.currentTimeMillis()}$suffix")
            tempFile.createNewFile()

            logger.debug("Temporary file created: ${tempFile.absolutePath}")
            return tempFile

        } catch (e: Exception) {
            logger.error("Failed to create temporary file", e)
            throw SDKError.FileSystemError("Failed to create temporary file: ${e.message}")
        }
    }

    /**
     * Write data to file
     * Equivalent to iOS FileManager write operations
     */
    actual suspend fun writeFile(path: String, data: ByteArray): Unit = mutex.withLock {
        logger.debug("Writing file: $path, size: ${data.size} bytes")

        try {
            val file = File(path)
            ensureDirectoryExists(file.parentFile)

            FileOutputStream(file).use { outputStream ->
                outputStream.write(data)
            }

            logger.debug("File written successfully: $path")

        } catch (e: Exception) {
            logger.error("Failed to write file: $path")
            throw SDKError.FileSystemError("Failed to write file: ${e.message}")
        }
    }

    /**
     * Read file data
     * Equivalent to iOS FileManager read operations
     */
    actual suspend fun readFile(path: String): ByteArray = mutex.withLock {
        logger.debug("Reading file: $path")

        return try {
            val file = File(path)
            if (!file.exists()) {
                logger.warn("File does not exist: $path")
                throw SDKError.FileSystemError("File not found: $path")
            }

            val data = file.readBytes()
            logger.debug("File read successfully: $path, size: ${data.size} bytes")
            data

        } catch (e: Exception) {
            logger.error("Failed to read file: $path")
            throw SDKError.FileSystemError("Failed to read file: ${e.message}")
        }
    }

    /**
     * Check if file exists
     * Equivalent to iOS FileManager file existence check
     */
    actual suspend fun fileExists(path: String): Boolean = mutex.withLock {
        return File(path).exists()
    }

    /**
     * Delete file
     * Equivalent to iOS FileManager file deletion
     */
    actual suspend fun deleteFile(path: String): Boolean = mutex.withLock {
        logger.debug("Deleting file: $path")

        return try {
            val file = File(path)
            val deleted = file.delete()

            if (deleted) {
                logger.debug("File deleted successfully: $path")
            } else {
                logger.warn("Failed to delete file: $path")
            }

            deleted

        } catch (e: Exception) {
            logger.error("Error deleting file: $path", e)
            false
        }
    }

    /**
     * Copy file
     * Equivalent to iOS FileManager file copying
     */
    suspend fun copyFile(sourcePath: String, destinationPath: String): Boolean = mutex.withLock {
        logger.debug("Copying file from: $sourcePath to: $destinationPath")

        return try {
            val sourceFile = File(sourcePath)
            val destinationFile = File(destinationPath)

            if (!sourceFile.exists()) {
                logger.error("Source file does not exist: $sourcePath")
                return false
            }

            ensureDirectoryExists(destinationFile.parentFile)
            sourceFile.copyTo(destinationFile, overwrite = true)

            logger.debug("File copied successfully")
            true

        } catch (e: Exception) {
            logger.error("Failed to copy file", e)
            false
        }
    }

    /**
     * Move file
     * Equivalent to iOS FileManager file moving
     */
    suspend fun moveFile(sourcePath: String, destinationPath: String): Boolean = mutex.withLock {
        logger.debug("Moving file from: $sourcePath to: $destinationPath")

        return try {
            val sourceFile = File(sourcePath)
            val destinationFile = File(destinationPath)

            if (!sourceFile.exists()) {
                logger.error("Source file does not exist: $sourcePath")
                return false
            }

            ensureDirectoryExists(destinationFile.parentFile)
            val moved = sourceFile.renameTo(destinationFile)

            if (moved) {
                logger.debug("File moved successfully")
            } else {
                logger.error("Failed to move file")
            }

            moved

        } catch (e: Exception) {
            logger.error("Failed to move file", e)
            false
        }
    }

    /**
     * Get file size
     * Equivalent to iOS FileManager file size queries
     */
    actual suspend fun getFileSize(path: String): Long = mutex.withLock {
        return try {
            val file = File(path)
            if (file.exists()) file.length() else 0L
        } catch (e: Exception) {
            logger.error("Failed to get file size: $path", e)
            0L
        }
    }

    /**
     * Calculate file checksum
     * For integrity verification
     */
    suspend fun calculateChecksum(path: String, algorithm: String = "SHA-256"): String? = mutex.withLock {
        logger.debug("Calculating $algorithm checksum for: $path")

        return try {
            val file = File(path)
            if (!file.exists()) {
                logger.warn("File does not exist for checksum: $path")
                return null
            }

            val digest = MessageDigest.getInstance(algorithm)
            file.inputStream().use { inputStream ->
                val buffer = ByteArray(8192)
                var bytesRead = 0

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }

            val checksum = digest.digest().joinToString("") { "%02x".format(it) }
            logger.debug("Checksum calculated: $checksum")
            checksum

        } catch (e: Exception) {
            logger.error("Failed to calculate checksum: $path", e)
            null
        }
    }

    /**
     * Clean up old files
     * Equivalent to iOS FileManager cleanup operations
     */
    suspend fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000L) = mutex.withLock {
        logger.debug("Cleaning up files older than $maxAge milliseconds")

        val cutoff = System.currentTimeMillis() - maxAge
        var deletedCount = 0
        var deletedSize = 0L

        try {
            // Clean temporary files
            tempDir.walkTopDown()
                .filter { it.isFile && it.lastModified() < cutoff }
                .forEach { file ->
                    try {
                        deletedSize += file.length()
                        if (file.delete()) {
                            deletedCount++
                        }
                    } catch (e: Exception) {
                        logger.warn("Failed to delete old file: ${file.absolutePath}: ${e.message}")
                    }
                }

            // Clean cache files
            cacheDir.walkTopDown()
                .filter { it.isFile && it.lastModified() < cutoff }
                .forEach { file ->
                    try {
                        deletedSize += file.length()
                        if (file.delete()) {
                            deletedCount++
                        }
                    } catch (e: Exception) {
                        logger.warn("Failed to delete old cache file: ${file.absolutePath}: ${e.message}")
                    }
                }

            logger.info("Cleanup completed: deleted $deletedCount files, ${deletedSize / 1024 / 1024} MB")

        } catch (e: Exception) {
            logger.error("Error during cleanup", e)
        }
    }

    /**
     * Get storage information
     * Equivalent to iOS FileManager storage queries
     */
    suspend fun getStorageInfo(): StorageInfo = mutex.withLock {
        logger.debug("Getting storage information")

        return try {
            val stat = StatFs(baseDir.absolutePath)
            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            val availableBlocks = stat.availableBlocksLong

            val totalSpace = totalBlocks * blockSize
            val availableSpace = availableBlocks * blockSize
            val usedSpace = calculateDirectorySize(baseDir)

            val modelCount = if (modelsDir.exists()) {
                modelsDir.listFiles()?.count { it.isFile } ?: 0
            } else {
                0
            }

            val cacheSize = if (cacheDir.exists()) {
                calculateDirectorySize(cacheDir)
            } else {
                0L
            }

            StorageInfo(
                totalSpace = totalSpace,
                availableSpace = availableSpace,
                usedSpace = usedSpace,
                modelCount = modelCount,
                cacheSize = cacheSize
            )

        } catch (e: Exception) {
            logger.error("Failed to get storage info", e)
            StorageInfo(0, 0, 0, 0, 0)
        }
    }

    /**
     * Get directory for specific type
     * Equivalent to iOS FileManager directory utilities
     */
    suspend fun getDirectory(type: DirectoryType): File = mutex.withLock {
        return when (type) {
            DirectoryType.MODELS -> modelsDir
            DirectoryType.CACHE -> cacheDir
            DirectoryType.TEMP -> tempDir
            DirectoryType.LOGS -> logsDir
            DirectoryType.DATABASE -> databaseDir
            DirectoryType.BASE -> baseDir
        }
    }

    /**
     * Ensure storage space is available
     * For proactive storage management
     */
    suspend fun ensureSpaceAvailable(requiredBytes: Long): Boolean = mutex.withLock {
        logger.debug("Checking space availability: ${requiredBytes / 1024 / 1024} MB required")

        val storageInfo = getStorageInfo()

        if (storageInfo.availableSpace >= requiredBytes) {
            logger.debug("Sufficient space available")
            return true
        }

        logger.info("Insufficient space, attempting cleanup")

        // Try cleanup and check again
        cleanupOldFiles(24 * 60 * 60 * 1000L) // 24 hours
        val updatedStorageInfo = getStorageInfo()

        val spaceAvailable = updatedStorageInfo.availableSpace >= requiredBytes
        logger.info("Space check after cleanup: ${updatedStorageInfo.availableSpace / 1024 / 1024} MB available")

        return spaceAvailable
    }

    /**
     * Create backup of important files
     * For data protection
     */
    suspend fun createBackup(sourcePath: String, backupSuffix: String = ".backup"): String? = mutex.withLock {
        logger.debug("Creating backup of: $sourcePath")

        return try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) {
                logger.warn("Source file does not exist for backup: $sourcePath")
                return null
            }

            val backupPath = "$sourcePath$backupSuffix"
            val success = copyFile(sourcePath, backupPath)

            if (success) {
                logger.info("Backup created: $backupPath")
                backupPath
            } else {
                logger.error("Failed to create backup")
                null
            }

        } catch (e: Exception) {
            logger.error("Error creating backup", e)
            null
        }
    }

    // Private helper methods

    private fun createDirectoryStructure() {
        try {
            val directories = listOf(baseDir, modelsDir, cacheDir, tempDir, logsDir, databaseDir)
            directories.forEach { dir ->
                if (!dir.exists()) {
                    dir.mkdirs()
                }
            }
            logger.debug("Directory structure created")

        } catch (e: Exception) {
            logger.error("Failed to create directory structure", e)
        }
    }

    private fun ensureDirectoryExists(directory: File?) {
        directory?.let { dir ->
            if (!dir.exists()) {
                dir.mkdirs()
            }
        }
    }

    private fun calculateDirectorySize(directory: File): Long {
        return try {
            if (!directory.exists()) return 0L

            directory.walkTopDown()
                .filter { it.isFile }
                .sumOf { it.length() }

        } catch (e: Exception) {
            logger.warn("Failed to calculate directory size: ${directory.absolutePath}: ${e.message}")
            0L
        }
    }

    // Missing actual methods from expect declaration
    actual suspend fun listFiles(directory: String): List<String> = mutex.withLock {
        val dir = File(directory)
        if (dir.exists() && dir.isDirectory) {
            dir.listFiles()?.map { it.absolutePath } ?: emptyList()
        } else {
            emptyList()
        }
    }

    actual suspend fun createDirectory(path: String) = mutex.withLock {
        val dir = File(path)
        if (!dir.exists()) {
            dir.mkdirs()
        }
    }

    actual suspend fun deleteDirectory(path: String) = mutex.withLock {
        val dir = File(path)
        if (dir.exists() && dir.isDirectory) {
            dir.deleteRecursively()
        }
    }

    actual suspend fun cleanupTempFiles() {
        mutex.withLock {
            tempDir.listFiles()?.forEach { file ->
                if (file.lastModified() < System.currentTimeMillis() - 24 * 60 * 60 * 1000) {
                    file.deleteRecursively()
                }
            }
        }
    }

    actual suspend fun getAvailableSpace(): Long = mutex.withLock {
        val stat = StatFs(baseDir.absolutePath)
        stat.availableBlocksLong * stat.blockSizeLong
    }

    actual suspend fun getTotalSpace(): Long = mutex.withLock {
        val stat = StatFs(baseDir.absolutePath)
        stat.blockCountLong * stat.blockSizeLong
    }

    actual suspend fun ensureDirectories() = mutex.withLock {
        createDirectoryStructure()
    }

    actual companion object {
        private var instance: FileManager? = null

        actual val shared: FileManager
            get() = instance ?: throw SDKError.NotInitialized

        actual val modelsDirectory: String
            get() = shared.modelsDir.absolutePath

        actual val cacheDirectory: String
            get() = shared.cacheDir.absolutePath

        actual val tempDirectory: String
            get() = shared.tempDir.absolutePath

        fun initialize(context: Context) {
            if (instance == null) {
                instance = FileManager().apply {
                    setContext(context)
                }
            }
        }
    }
}

/**
 * Directory type enumeration
 * Equivalent to iOS directory types
 */
enum class DirectoryType {
    BASE,
    MODELS,
    CACHE,
    TEMP,
    LOGS,
    DATABASE
}

/**
 * Storage information data class
 * Equivalent to iOS storage info
 */
data class StorageInfo(
    val totalSpace: Long,
    val availableSpace: Long,
    val usedSpace: Long,
    val modelCount: Int,
    val cacheSize: Long
) {

    val usedSpacePercent: Float
        get() = if (totalSpace > 0) (usedSpace.toFloat() / totalSpace) * 100 else 0f

    val availableSpacePercent: Float
        get() = if (totalSpace > 0) (availableSpace.toFloat() / totalSpace) * 100 else 0f

    fun formatSize(bytes: Long): String {
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var size = bytes.toDouble()
        var unitIndex = 0

        while (size >= 1024 && unitIndex < units.size - 1) {
            size /= 1024
            unitIndex++
        }

        return String.format("%.1f %s", size, units[unitIndex])
    }

    val totalSpaceFormatted: String
        get() = formatSize(totalSpace)

    val availableSpaceFormatted: String
        get() = formatSize(availableSpace)

    val usedSpaceFormatted: String
        get() = formatSize(usedSpace)

    val cacheSizeFormatted: String
        get() = formatSize(cacheSize)
}
