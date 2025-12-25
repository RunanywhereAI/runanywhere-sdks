package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.URL

private val logger = SDKLogger("ONNXDownloadStrategyImpl")

/**
 * Download a file from URL to destination folder
 */
actual suspend fun downloadFile(
    url: String,
    destinationFolder: String,
    progressHandler: ((Double) -> Unit)?,
): String =
    withContext(Dispatchers.IO) {
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
 * Supports tar.bz2 and tar.gz formats using Apache Commons Compress
 */
actual suspend fun extractArchive(
    archivePath: String,
    destinationFolder: String,
): String =
    withContext(Dispatchers.IO) {
        logger.info("Extracting archive: $archivePath to $destinationFolder")

        val destDir = File(destinationFolder)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        // First try native extraction via RunAnywhereBridge (if libarchive is available)
        try {
            val result = ONNXCoreService.extractArchive(archivePath, destinationFolder)
            if (result.isSuccess) {
                logger.info("Extracted archive using native library")
                cleanupArchiveFile(archivePath)
                return@withContext destinationFolder
            } else {
                logger.debug("Native extraction returned: $result, falling back to Java extraction")
            }
        } catch (e: Exception) {
            logger.debug("Native extraction not available: ${e.message}, using Java extraction")
        }

        // Fallback: Use Apache Commons Compress for tar.bz2/tar.gz
        try {
            when {
                archivePath.endsWith(".tar.bz2") -> extractTarBz2(archivePath, destDir)
                archivePath.endsWith(".tar.gz") || archivePath.endsWith(".tgz") -> extractTarGz(archivePath, destDir)
                else -> throw ONNXError.ModelLoadFailed("Unsupported archive format: $archivePath")
            }

            logger.info("Extracted archive using Java/Kotlin (Commons Compress)")
            cleanupArchiveFile(archivePath)
            return@withContext destinationFolder
        } catch (e: ONNXError) {
            throw e
        } catch (e: Exception) {
            logger.error("Java extraction failed: ${e.message}")
            throw ONNXError.ModelLoadFailed("Archive extraction failed: ${e.message}")
        }
    }

/**
 * Delete archive file after extraction
 */
private fun cleanupArchiveFile(archivePath: String) {
    try {
        File(archivePath).delete()
        logger.debug("Deleted archive file: $archivePath")
    } catch (e: Exception) {
        logger.warning("Could not delete archive file: ${e.message}")
    }
}

/**
 * Extract tar.bz2 archive using Apache Commons Compress
 */
private fun extractTarBz2(archivePath: String, destDir: File) {
    logger.info("Extracting tar.bz2 using Apache Commons Compress")

    FileInputStream(archivePath).use { fileIn ->
        BufferedInputStream(fileIn).use { bufferedIn ->
            BZip2CompressorInputStream(bufferedIn).use { bz2In ->
                TarArchiveInputStream(bz2In).use { tarIn ->
                    extractTarEntries(tarIn, destDir)
                }
            }
        }
    }
}

/**
 * Extract tar.gz archive using Apache Commons Compress
 */
private fun extractTarGz(archivePath: String, destDir: File) {
    logger.info("Extracting tar.gz using Apache Commons Compress")

    FileInputStream(archivePath).use { fileIn ->
        BufferedInputStream(fileIn).use { bufferedIn ->
            GzipCompressorInputStream(bufferedIn).use { gzIn ->
                TarArchiveInputStream(gzIn).use { tarIn ->
                    extractTarEntries(tarIn, destDir)
                }
            }
        }
    }
}

/**
 * Extract entries from a tar archive
 */
private fun extractTarEntries(tarIn: TarArchiveInputStream, destDir: File) {
    var entry: TarArchiveEntry? = tarIn.nextEntry
    var fileCount = 0

    while (entry != null) {
        val outputFile = File(destDir, entry.name)

        // Security check: prevent path traversal
        if (!outputFile.canonicalPath.startsWith(destDir.canonicalPath)) {
            logger.warning("Skipping potentially unsafe entry: ${entry.name}")
            entry = tarIn.nextEntry
            continue
        }

        if (entry.isDirectory) {
            outputFile.mkdirs()
        } else {
            // Ensure parent directories exist
            outputFile.parentFile?.mkdirs()

            // Extract file
            FileOutputStream(outputFile).use { output ->
                val buffer = ByteArray(8192)
                var len: Int
                while (tarIn.read(buffer).also { len = it } != -1) {
                    output.write(buffer, 0, len)
                }
            }
            fileCount++
        }

        entry = tarIn.nextEntry
    }

    logger.info("Extracted $fileCount files from tar archive")
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
 *
 * For Sherpa-ONNX models (whisper, zipformer), returns the DIRECTORY containing
 * encoder.onnx, decoder.onnx, and tokens.txt files.
 * For simple single-file models, returns the .onnx file path.
 */
actual fun findONNXModelPath(modelId: String, folder: String): String? {
    val folderFile = File(folder)
    if (!folderFile.exists()) return null

    // Helper to check if a directory contains sherpa-onnx model structure
    fun isSherpaOnnxModelDir(dir: File): Boolean {
        val files = dir.listFiles() ?: return false
        val hasEncoder = files.any { it.name.contains("encoder") && it.extension == "onnx" }
        val hasDecoder = files.any { it.name.contains("decoder") && it.extension == "onnx" }
        val hasTokens = files.any { it.name.contains("tokens") && it.extension == "txt" }
        return (hasEncoder && hasDecoder) || hasTokens
    }

    // Check if current folder is a sherpa-onnx model directory
    if (isSherpaOnnxModelDir(folderFile)) {
        logger.debug("Found sherpa-onnx model directory: ${folderFile.absolutePath}")
        return folderFile.absolutePath
    }

    // Check current folder for single .onnx file (simple models)
    folderFile.listFiles()?.forEach { file ->
        if (file.isFile && file.extension.lowercase() == "onnx") {
            return file.absolutePath
        }
    }

    // Check one level deep (sherpa-onnx archives extract to a subdirectory)
    folderFile.listFiles()?.filter { it.isDirectory }?.forEach { subDir ->
        // Check if this subdirectory is a sherpa-onnx model directory
        if (isSherpaOnnxModelDir(subDir)) {
            logger.debug("Found sherpa-onnx model directory in subdir: ${subDir.absolutePath}")
            return subDir.absolutePath
        }

        // Check for single .onnx file
        subDir.listFiles()?.forEach { file ->
            if (file.isFile && file.extension.lowercase() == "onnx") {
                return file.absolutePath
            }
        }

        // Check two levels deep (for nested sherpa-onnx structure)
        subDir.listFiles()?.filter { it.isDirectory }?.forEach { subSubDir ->
            if (isSherpaOnnxModelDir(subSubDir)) {
                logger.debug("Found sherpa-onnx model directory (level 2): ${subSubDir.absolutePath}")
                return subSubDir.absolutePath
            }

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

// Archive extraction is handled by:
// 1. Native ra_extract_archive() via runanywhere-core (if libarchive is available - iOS/macOS)
// 2. Apache Commons Compress (fallback for Android/JVM)
