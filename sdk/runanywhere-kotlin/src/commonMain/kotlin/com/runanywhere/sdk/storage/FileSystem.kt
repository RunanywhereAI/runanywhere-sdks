package com.runanywhere.sdk.storage

import kotlinx.coroutines.runBlocking

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
     * Append bytes to an existing file
     * If file doesn't exist, creates it and writes the data
     */
    suspend fun appendBytes(path: String, data: ByteArray)

    /**
     * Write to a file using an output stream (for efficient streaming)
     * The output stream is automatically closed when the block completes
     */
    suspend fun <T> writeStream(path: String, block: suspend (java.io.OutputStream) -> T): T

    /**
     * Read bytes from a file
     */
    suspend fun readBytes(path: String): ByteArray

    /**
     * Check if a file or directory exists
     */
    suspend fun exists(path: String): Boolean

    /**
     * Check if a file or directory exists (synchronous version)
     */
    fun existsSync(path: String): Boolean = runBlocking { exists(path) }

    /**
     * Check if path is a directory (synchronous version)
     */
    fun isDirectorySync(path: String): Boolean = runBlocking { isDirectory(path) }

    /**
     * List files in a directory (synchronous version)
     */
    fun listSync(path: String): List<String> = runBlocking { listFiles(path) }

    /**
     * Delete a file or directory
     */
    suspend fun delete(path: String): Boolean

    /**
     * Delete a directory and all its contents recursively
     */
    suspend fun deleteRecursively(path: String): Boolean

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
