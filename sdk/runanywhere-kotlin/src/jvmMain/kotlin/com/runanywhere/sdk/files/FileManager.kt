package com.runanywhere.sdk.files

import java.io.File
import java.security.MessageDigest

actual fun calculateSHA256(data: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val hash = digest.digest(data)
    return hash.joinToString("") { "%02x".format(it) }
}

actual class FileManager {
    actual suspend fun ensureDirectories() {
        File(modelsDirectory).mkdirs()
        File(cacheDirectory).mkdirs()
        File(tempDirectory).mkdirs()
    }

    actual suspend fun writeFile(path: String, data: ByteArray) {
        File(path).writeBytes(data)
    }

    actual suspend fun readFile(path: String): ByteArray {
        return File(path).readBytes()
    }

    actual suspend fun fileExists(path: String): Boolean {
        return File(path).exists()
    }

    actual suspend fun deleteFile(path: String): Boolean {
        return File(path).delete()
    }

    actual suspend fun getFileSize(path: String): Long {
        return File(path).length()
    }

    actual suspend fun listFiles(directory: String): List<String> {
        return File(directory).listFiles()?.map { it.name } ?: emptyList()
    }

    actual suspend fun createDirectory(path: String) {
        File(path).mkdirs()
    }

    actual suspend fun deleteDirectory(path: String) {
        File(path).deleteRecursively()
    }

    actual fun getModelPath(modelId: String): String {
        return "$modelsDirectory/$modelId.bin"
    }

    actual fun getCachePath(fileName: String): String {
        return "$cacheDirectory/$fileName"
    }

    actual fun getTempPath(fileName: String): String {
        return "$tempDirectory/$fileName"
    }

    actual suspend fun cleanupTempFiles() {
        File(tempDirectory).deleteRecursively()
        File(tempDirectory).mkdirs()
    }

    actual suspend fun getAvailableSpace(): Long {
        return File(".").freeSpace
    }

    actual suspend fun getTotalSpace(): Long {
        return File(".").totalSpace
    }

    actual companion object {
        actual val shared: FileManager = FileManager()
        actual val modelsDirectory: String = "${System.getProperty("user.home")}/.runanywhere/models"
        actual val cacheDirectory: String = "${System.getProperty("user.home")}/.runanywhere/cache"
        actual val tempDirectory: String = "${System.getProperty("user.home")}/.runanywhere/temp"
    }
}
