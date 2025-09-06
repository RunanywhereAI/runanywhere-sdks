package com.runanywhere.sdk.storage

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * JVM implementation of FileSystem using java.io.File
 */
internal class JvmFileSystem : FileSystem {

    override suspend fun writeBytes(path: String, data: ByteArray) = withContext(Dispatchers.IO) {
        File(path).writeBytes(data)
    }

    override suspend fun readBytes(path: String): ByteArray = withContext(Dispatchers.IO) {
        File(path).readBytes()
    }

    override suspend fun exists(path: String): Boolean = withContext(Dispatchers.IO) {
        File(path).exists()
    }

    override suspend fun delete(path: String): Boolean = withContext(Dispatchers.IO) {
        File(path).deleteRecursively()
    }

    override suspend fun createDirectory(path: String): Boolean = withContext(Dispatchers.IO) {
        File(path).mkdirs()
    }

    override suspend fun fileSize(path: String): Long = withContext(Dispatchers.IO) {
        File(path).length()
    }

    override suspend fun listFiles(path: String): List<String> = withContext(Dispatchers.IO) {
        File(path).listFiles()?.map { it.absolutePath } ?: emptyList()
    }

    override suspend fun move(from: String, to: String): Boolean = withContext(Dispatchers.IO) {
        try {
            File(from).renameTo(File(to))
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun copy(from: String, to: String): Boolean = withContext(Dispatchers.IO) {
        try {
            File(from).copyTo(File(to), overwrite = true)
            true
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun isDirectory(path: String): Boolean = withContext(Dispatchers.IO) {
        File(path).isDirectory
    }

    override fun getCacheDirectory(): String {
        return System.getProperty("java.io.tmpdir") ?: "/tmp"
    }

    override fun getDataDirectory(): String {
        return System.getProperty("user.home") + "/.runanywhere"
    }

    override fun getTempDirectory(): String {
        return System.getProperty("java.io.tmpdir") ?: "/tmp"
    }
}

/**
 * Factory function to create FileSystem for JVM
 */
actual fun createFileSystem(): FileSystem = JvmFileSystem()
