package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.URL

private val logger = SDKLogger("LlamaCppDownloadStrategyImpl")

/**
 * Download a GGUF file from URL to destination folder
 */
internal actual suspend fun downloadGGUFFile(
    url: String,
    modelId: String,
    destinationFolder: String,
    progressHandler: ((Double) -> Unit)?,
): String =
    withContext(Dispatchers.IO) {
        logger.info("Downloading GGUF file from: $url")

        val destDir = File(destinationFolder)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        // Use original filename from URL
        val fileName = url.substringAfterLast("/")
        val destFile = File(destDir, fileName)

        val connection = URL(url).openConnection()
        val totalSize = connection.contentLengthLong
        var downloadedSize = 0L

        connection.getInputStream().use { input ->
            FileOutputStream(destFile).use { output ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                    downloadedSize += bytesRead
                    if (totalSize > 0) {
                        progressHandler?.invoke(downloadedSize.toDouble() / totalSize)
                    }
                }
            }
        }

        logger.info("Downloaded GGUF file to: ${destFile.absolutePath}")
        destFile.absolutePath
    }

/**
 * Create a directory
 */
internal actual fun createDirectory(path: String) {
    val dir = File(path)
    if (!dir.exists()) {
        dir.mkdirs()
    }
}

/**
 * Find GGUF model path in a folder
 */
internal actual fun findGGUFModelPath(modelId: String, folder: String): String? {
    val folderFile = File(folder)
    if (!folderFile.exists()) return null

    // Check current folder for .gguf or .ggml file
    folderFile.listFiles()?.forEach { file ->
        if (file.isFile) {
            val ext = file.extension.lowercase()
            if (ext == "gguf" || ext == "ggml") {
                return file.absolutePath
            }
        }
    }

    // Check one level deep
    folderFile.listFiles()?.filter { it.isDirectory }?.forEach { subDir ->
        subDir.listFiles()?.forEach { file ->
            if (file.isFile) {
                val ext = file.extension.lowercase()
                if (ext == "gguf" || ext == "ggml") {
                    return file.absolutePath
                }
            }
        }
    }

    return null
}

/**
 * Detect GGUF model in folder
 */
internal actual fun detectGGUFModel(folder: String): Pair<ModelFormat, Long>? {
    val modelPath = findGGUFModelPath("", folder) ?: return null
    val modelFile = File(modelPath)
    return Pair(ModelFormat.GGUF, modelFile.length())
}

/**
 * Check if folder contains valid GGUF model
 */
internal actual fun isValidGGUFModelStorage(folder: String): Boolean {
    return findGGUFModelPath("", folder) != null
}
