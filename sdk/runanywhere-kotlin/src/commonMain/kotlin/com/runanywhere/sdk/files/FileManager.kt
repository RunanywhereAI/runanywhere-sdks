package com.runanywhere.sdk.files

/**
 * Platform-specific hash calculation
 */
expect fun calculateSHA256(data: ByteArray): String

/**
 * Common FileManager interface for cross-platform file operations
 */
expect class FileManager {
    suspend fun ensureDirectories()
    suspend fun writeFile(path: String, data: ByteArray)
    suspend fun readFile(path: String): ByteArray
    suspend fun fileExists(path: String): Boolean
    suspend fun deleteFile(path: String): Boolean
    suspend fun getFileSize(path: String): Long
    suspend fun getDirectorySize(path: String): Long
    suspend fun listFiles(directory: String): List<String>
    suspend fun createDirectory(path: String)
    suspend fun deleteDirectory(path: String)

    // Model-specific operations
    fun getModelPath(modelId: String): String
    fun getCachePath(fileName: String): String
    fun getTempPath(fileName: String): String

    // Storage management
    suspend fun cleanupTempFiles()
    suspend fun getAvailableSpace(): Long
    suspend fun getTotalSpace(): Long

    companion object {
        val shared: FileManager
        val modelsDirectory: String
        val cacheDirectory: String
        val tempDirectory: String
    }
}
