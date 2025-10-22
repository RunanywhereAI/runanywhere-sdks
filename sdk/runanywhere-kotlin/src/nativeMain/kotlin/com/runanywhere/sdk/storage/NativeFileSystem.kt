package com.runanywhere.sdk.storage

/**
 * Native implementation of FileSystem
 * This is a basic implementation - in production you would use platform-specific APIs
 */
internal class NativeFileSystem : FileSystem {

    // In-memory file system simulation for native platforms
    private val files = mutableMapOf<String, ByteArray>()
    private val directories = mutableSetOf<String>()

    override suspend fun writeBytes(path: String, data: ByteArray) {
        files[path] = data
        // Add parent directories
        val parent = path.substringBeforeLast('/', "")
        if (parent.isNotEmpty()) {
            directories.add(parent)
        }
    }

    override suspend fun readBytes(path: String): ByteArray {
        return files[path] ?: throw IllegalArgumentException("File not found: $path")
    }

    override suspend fun exists(path: String): Boolean {
        return files.containsKey(path) || directories.contains(path)
    }

    override suspend fun delete(path: String): Boolean {
        return if (files.containsKey(path)) {
            files.remove(path)
            true
        } else if (directories.contains(path)) {
            // Remove directory and all its contents
            val prefix = "$path/"
            files.keys.filter { it.startsWith(prefix) }.forEach { files.remove(it) }
            directories.removeAll { it.startsWith(path) }
            true
        } else {
            false
        }
    }

    override suspend fun createDirectory(path: String): Boolean {
        directories.add(path)
        // Add parent directories
        var parent = path
        while (parent.contains('/')) {
            parent = parent.substringBeforeLast('/')
            if (parent.isNotEmpty()) {
                directories.add(parent)
            }
        }
        return true
    }

    override suspend fun fileSize(path: String): Long {
        return files[path]?.size?.toLong() ?: 0L
    }

    override suspend fun listFiles(path: String): List<String> {
        val prefix = if (path.endsWith('/')) path else "$path/"
        return files.keys.filter {
            it.startsWith(prefix) && !it.substring(prefix.length).contains('/')
        }
    }

    override suspend fun move(from: String, to: String): Boolean {
        return files[from]?.let { data ->
            files.remove(from)
            files[to] = data
            true
        } ?: false
    }

    override suspend fun copy(from: String, to: String): Boolean {
        return files[from]?.let { data ->
            files[to] = data
            true
        } ?: false
    }

    override suspend fun isDirectory(path: String): Boolean {
        return directories.contains(path)
    }

    override fun getCacheDirectory(): String {
        return "/tmp/cache"
    }

    override fun getDataDirectory(): String {
        return "/data"
    }

    override fun getTempDirectory(): String {
        return "/tmp"
    }
}

/**
 * Factory function to create FileSystem for native platforms
 */
actual fun createFileSystem(): FileSystem = NativeFileSystem()
