package com.runanywhere.sdk.infrastructure.modelmanagement.services

import java.io.File

/**
 * Get current time in milliseconds (JVM/Android implementation)
 */
internal actual fun currentTimeMillis(): Long = System.currentTimeMillis()

/**
 * Create a directory if it doesn't exist (JVM/Android implementation)
 */
internal actual fun createDirectoryIfNeeded(path: String) {
    val dir = File(path)
    if (!dir.exists()) {
        dir.mkdirs()
    }
}

/**
 * List contents of a directory (JVM/Android implementation)
 */
internal actual fun listDirectoryContents(path: String): List<String>? {
    val dir = File(path)
    if (!dir.isDirectory) return null
    return dir.list()?.toList()
}

/**
 * Check if a path is a directory (JVM/Android implementation)
 */
internal actual fun isDirectoryPath(path: String): Boolean {
    return File(path).isDirectory
}

/**
 * Calculate total size and file count for a directory (JVM/Android implementation)
 */
internal actual fun calculateDirectorySize(directory: String): Pair<Long, Int> {
    val dir = File(directory)
    if (!dir.isDirectory) return Pair(0L, 0)

    var totalSize = 0L
    var fileCount = 0

    dir.walkTopDown().forEach { file ->
        if (file.isFile) {
            totalSize += file.length()
            fileCount++
        }
    }

    return Pair(totalSize, fileCount)
}
