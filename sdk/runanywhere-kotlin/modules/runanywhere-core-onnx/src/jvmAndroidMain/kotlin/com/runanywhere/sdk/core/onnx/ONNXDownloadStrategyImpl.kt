package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.URL

private val logger = SDKLogger("ONNXDownloadStrategyImpl")

/**
 * Download a file from URL to destination folder
 */
actual suspend fun downloadFile(
    url: String,
    destinationFolder: String,
    progressHandler: ((Double) -> Unit)?
): String = withContext(Dispatchers.IO) {
    logger.info("Downloading file from: $url")

    val destDir = File(destinationFolder)
    if (!destDir.exists()) {
        destDir.mkdirs()
    }

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

    logger.info("Downloaded file to: ${destFile.absolutePath}")
    destFile.absolutePath
}

/**
 * Extract an archive to destination folder
 */
actual suspend fun extractArchive(
    archivePath: String,
    destinationFolder: String
): String = withContext(Dispatchers.IO) {
    logger.info("Extracting archive: $archivePath")

    val destDir = File(destinationFolder)
    if (!destDir.exists()) {
        destDir.mkdirs()
    }

    // Use native extraction if available (via RunAnywhereBridge)
    try {
        val result = ONNXCoreService.extractArchive(archivePath, destinationFolder)
        if (result.isSuccess) {
            logger.info("Extracted archive using native library")
            return@withContext destinationFolder
        }
    } catch (e: Exception) {
        logger.warning("Native extraction failed, falling back to Java: ${e.message}")
    }

    // Fallback: Java-based extraction for tar.gz/tar.bz2
    val archiveFile = File(archivePath)
    when {
        archivePath.endsWith(".tar.gz") || archivePath.endsWith(".tgz") -> {
            extractTarGz(archiveFile, destDir)
        }
        archivePath.endsWith(".tar.bz2") -> {
            extractTarBz2(archiveFile, destDir)
        }
        else -> {
            throw ONNXError.ModelLoadFailed("Unsupported archive format: $archivePath")
        }
    }

    logger.info("Extracted archive to: $destinationFolder")
    destinationFolder
}

/**
 * Create a directory
 */
actual fun createDirectory(path: String) {
    val dir = File(path)
    if (!dir.exists()) {
        dir.mkdirs()
    }
}

/**
 * Find ONNX model path in a folder (recursive up to 2 levels)
 */
actual fun findONNXModelPath(modelId: String, folder: String): String? {
    val folderFile = File(folder)
    if (!folderFile.exists()) return null

    // Check current folder for .onnx files
    folderFile.listFiles()?.forEach { file ->
        if (file.isFile && file.extension.lowercase() == "onnx") {
            return file.absolutePath
        }
    }

    // Check one level deep
    folderFile.listFiles()?.filter { it.isDirectory }?.forEach { subDir ->
        subDir.listFiles()?.forEach { file ->
            if (file.isFile && file.extension.lowercase() == "onnx") {
                return file.absolutePath
            }
        }

        // Check two levels deep (for sherpa-onnx structure)
        subDir.listFiles()?.filter { it.isDirectory }?.forEach { subSubDir ->
            subSubDir.listFiles()?.forEach { file ->
                if (file.isFile && file.extension.lowercase() == "onnx") {
                    return file.absolutePath
                }
            }
        }
    }

    return null
}

/**
 * Detect ONNX model in folder
 */
actual fun detectONNXModel(folder: String): Pair<ModelFormat, Long>? {
    val modelPath = findONNXModelPath("", folder) ?: return null
    val modelFile = File(modelPath)
    return Pair(ModelFormat.ONNX, modelFile.length())
}

/**
 * Check if folder contains valid ONNX model
 */
actual fun isValidONNXModelStorage(folder: String): Boolean {
    return findONNXModelPath("", folder) != null
}

// MARK: - Private Helpers

/**
 * Extract tar.gz archive (placeholder - requires Apache Commons Compress or similar)
 */
private fun extractTarGz(archive: File, destDir: File) {
    // In a real implementation, use Apache Commons Compress or similar library
    // For now, throw an error indicating the limitation
    logger.warning("tar.gz extraction requires Apache Commons Compress library")
    throw ONNXError.NotImplemented
}

/**
 * Extract tar.bz2 archive (placeholder - requires Apache Commons Compress or similar)
 */
private fun extractTarBz2(archive: File, destDir: File) {
    // In a real implementation, use Apache Commons Compress or similar library
    // For now, throw an error indicating the limitation
    logger.warning("tar.bz2 extraction requires Apache Commons Compress library")
    throw ONNXError.NotImplemented
}
