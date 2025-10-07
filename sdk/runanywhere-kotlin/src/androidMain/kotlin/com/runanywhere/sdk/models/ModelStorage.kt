package com.runanywhere.sdk.models

import java.io.File

/**
 * Android implementation of platform file operations
 */
actual class PlatformFile(private val file: File) {
    actual val path: String = file.absolutePath
    actual fun exists(): Boolean = file.exists()
    actual fun delete(): Boolean = file.delete()
    actual fun length(): Long = file.length()
    actual val name: String = file.name
    actual val nameWithoutExtension: String = file.nameWithoutExtension
    actual fun isFile(): Boolean = file.isFile
}

actual fun createPlatformFile(path: String): PlatformFile = PlatformFile(File(path))

actual fun getPlatformBaseDir(): String = System.getProperty("user.home")

actual fun createDirectory(path: String): Boolean {
    val dir = File(path)
    return dir.exists() || dir.mkdirs()
}

actual fun listFiles(directory: String): List<PlatformFile> {
    val dir = File(directory)
    return dir.listFiles()?.map { PlatformFile(it) } ?: emptyList()
}
