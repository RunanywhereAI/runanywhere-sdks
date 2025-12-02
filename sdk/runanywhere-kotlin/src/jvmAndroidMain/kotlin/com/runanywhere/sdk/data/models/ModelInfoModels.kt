package com.runanywhere.sdk.data.models

import java.io.File

/**
 * Platform-specific file/directory existence check
 * Matches iOS FileManager.default.fileExists behavior
 * Works for both files and directories
 */
actual fun fileExists(path: String): Boolean {
    val file = File(path)
    if (!file.exists()) return false

    // For directories, check if they contain at least one file (matching iOS behavior)
    if (file.isDirectory) {
        val contents = file.listFiles()
        return contents != null && contents.isNotEmpty()
    }

    return true
}
