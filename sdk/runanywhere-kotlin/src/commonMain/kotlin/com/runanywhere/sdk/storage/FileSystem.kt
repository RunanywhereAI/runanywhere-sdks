package com.runanywhere.sdk.storage

/**
 * Platform-agnostic file system abstraction
 * Provides common file operations that are implemented differently on each platform
 */
interface FileSystem {
    /**
     * Write bytes to a file
     */
    suspend fun writeBytes(path: String, data: ByteArray)

    /**
     * Read bytes from a file
     */
    suspend fun readBytes(path: String): ByteArray

    /**
     * Check if a file or directory exists
     */
    suspend fun exists(path: String): Boolean

    /**
     * Delete a file or directory
     */
    suspend fun delete(path: String): Boolean

    /**
     * Create a directory (including parent directories if needed)
     */
    suspend fun createDirectory(path: String): Boolean

    /**
     * Get the size of a file in bytes
     */
    suspend fun fileSize(path: String): Long

    /**
     * List files in a directory
     */
    suspend fun listFiles(path: String): List<String>

    /**
     * Move/rename a file
     */
    suspend fun move(from: String, to: String): Boolean

    /**
     * Copy a file
     */
    suspend fun copy(from: String, to: String): Boolean

    /**
     * Check if path is a directory
     */
    suspend fun isDirectory(path: String): Boolean

    /**
     * Get the app's cache directory path
     */
    fun getCacheDirectory(): String

    /**
     * Get the app's data directory path
     */
    fun getDataDirectory(): String

    /**
     * Get a temporary directory path
     */
    fun getTempDirectory(): String
}

/**
 * Expected to be provided by each platform
 */
expect fun createFileSystem(): FileSystem
