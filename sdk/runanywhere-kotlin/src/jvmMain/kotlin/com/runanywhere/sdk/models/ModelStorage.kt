package com.runanywhere.sdk.models

import java.io.File

actual class PlatformFile(private val file: File) {
    actual val path: String
        get() = file.absolutePath

    actual fun exists(): Boolean = file.exists()

    actual fun delete(): Boolean = file.delete()

    actual fun length(): Long = file.length()

    actual val name: String
        get() = file.name

    actual val nameWithoutExtension: String
        get() = file.nameWithoutExtension

    actual fun isFile(): Boolean = file.isFile
}

actual fun createPlatformFile(path: String): PlatformFile {
    return PlatformFile(File(path))
}

actual fun getPlatformBaseDir(): String {
    return File(System.getProperty("user.home") ?: "/tmp", ".runanywhere").absolutePath
}

actual fun createDirectory(path: String): Boolean {
    val dir = File(path)
    return dir.mkdirs()
}

actual fun listFiles(directory: String): List<PlatformFile> {
    val dir = File(directory)
    return dir.listFiles()?.map { PlatformFile(it) } ?: emptyList()
}
