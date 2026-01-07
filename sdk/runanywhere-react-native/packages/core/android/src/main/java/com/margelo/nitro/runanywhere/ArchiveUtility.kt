/**
 * ArchiveUtility.kt
 *
 * Native archive extraction utility for Android.
 * Uses Java's native GZIPInputStream for gzip decompression
 * and pure Kotlin tar extraction.
 *
 * Mirrors the implementation from:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift
 *
 * Supports: tar.gz, zip
 */

package com.margelo.nitro.runanywhere

import android.util.Log
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.ZipInputStream

/**
 * Utility for handling archive extraction on Android
 */
object ArchiveUtility {
    private const val TAG = "ArchiveUtility"
    private const val TAR_BLOCK_SIZE = 512

    /**
     * Extract an archive to a destination directory
     * @param archivePath Path to the archive file
     * @param destinationPath Destination directory path
     * @return true if extraction succeeded
     */
    @JvmStatic
    fun extract(archivePath: String, destinationPath: String): Boolean {
        return try {
            extractArchive(archivePath, destinationPath)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Extraction failed: ${e.message}", e)
            false
        }
    }

    /**
     * Extract an archive to a destination directory (throwing version)
     */
    @Throws(Exception::class)
    fun extractArchive(
        archivePath: String,
        destinationPath: String,
        progressHandler: ((Double) -> Unit)? = null
    ) {
        val archiveFile = File(archivePath)
        val destinationDir = File(destinationPath)

        if (!archiveFile.exists()) {
            throw Exception("Archive not found: $archivePath")
        }

        // Detect archive type by magic bytes (more reliable than file extension)
        val archiveType = detectArchiveTypeByMagicBytes(archiveFile)
        Log.i(TAG, "Detected archive type: $archiveType for: $archivePath")

        when (archiveType) {
            ArchiveType.GZIP -> {
                extractTarGz(archiveFile, destinationDir, progressHandler)
            }
            ArchiveType.ZIP -> {
                extractZip(archiveFile, destinationDir, progressHandler)
            }
            ArchiveType.BZIP2 -> {
                throw Exception("tar.bz2 format requires Apache Commons Compress. Use tar.gz instead.")
            }
            ArchiveType.XZ -> {
                throw Exception("tar.xz format requires Apache Commons Compress. Use tar.gz instead.")
            }
            ArchiveType.UNKNOWN -> {
                // Fallback to file extension check
                val lowercased = archivePath.lowercase()
                when {
                    lowercased.endsWith(".tar.gz") || lowercased.endsWith(".tgz") -> {
                        extractTarGz(archiveFile, destinationDir, progressHandler)
                    }
                    lowercased.endsWith(".zip") -> {
                        extractZip(archiveFile, destinationDir, progressHandler)
                    }
                    else -> {
                        throw Exception("Unknown archive format: $archivePath")
                    }
                }
            }
        }
    }

    /**
     * Archive type detected by magic bytes
     */
    private enum class ArchiveType {
        GZIP, ZIP, BZIP2, XZ, UNKNOWN
    }

    /**
     * Detect archive type by reading magic bytes from file header
     */
    private fun detectArchiveTypeByMagicBytes(file: File): ArchiveType {
        return try {
            FileInputStream(file).use { fis ->
                val header = ByteArray(6)
                val bytesRead = fis.read(header)
                if (bytesRead < 2) return ArchiveType.UNKNOWN

                // Check for gzip: 0x1f 0x8b
                if (header[0] == 0x1f.toByte() && header[1] == 0x8b.toByte()) {
                    return ArchiveType.GZIP
                }

                // Check for zip: 0x50 0x4b 0x03 0x04 ("PK\x03\x04")
                if (bytesRead >= 4 &&
                    header[0] == 0x50.toByte() && header[1] == 0x4b.toByte() &&
                    header[2] == 0x03.toByte() && header[3] == 0x04.toByte()) {
                    return ArchiveType.ZIP
                }

                // Check for bzip2: 0x42 0x5a ("BZ")
                if (header[0] == 0x42.toByte() && header[1] == 0x5a.toByte()) {
                    return ArchiveType.BZIP2
                }

                // Check for xz: 0xfd 0x37 0x7a 0x58 0x5a 0x00
                if (bytesRead >= 6 &&
                    header[0] == 0xfd.toByte() && header[1] == 0x37.toByte() &&
                    header[2] == 0x7a.toByte() && header[3] == 0x58.toByte() &&
                    header[4] == 0x5a.toByte() && header[5] == 0x00.toByte()) {
                    return ArchiveType.XZ
                }

                ArchiveType.UNKNOWN
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to detect archive type: ${e.message}")
            ArchiveType.UNKNOWN
        }
    }

    // MARK: - tar.gz Extraction

    /**
     * Extract a tar.gz archive using Java's native GZIPInputStream
     */
    private fun extractTarGz(
        sourceFile: File,
        destinationDir: File,
        progressHandler: ((Double) -> Unit)?
    ) {
        val startTime = System.currentTimeMillis()
        Log.i(TAG, "Extracting tar.gz: ${sourceFile.name}")
        progressHandler?.invoke(0.0)

        // Step 1: Decompress gzip to get tar data
        Log.i(TAG, "Starting native gzip decompression...")
        val tarData = decompressGzip(sourceFile)
        val decompressTime = System.currentTimeMillis()
        Log.i(TAG, "Decompressed to ${formatBytes(tarData.size.toLong())} in ${decompressTime - startTime}ms")
        progressHandler?.invoke(0.3)

        // Step 2: Extract tar archive
        Log.i(TAG, "Extracting tar data...")
        extractTarData(tarData, destinationDir) { progress ->
            progressHandler?.invoke(0.3 + progress * 0.7)
        }

        val totalTime = System.currentTimeMillis() - startTime
        Log.i(TAG, "Total extraction time: ${totalTime}ms")
        progressHandler?.invoke(1.0)
    }

    /**
     * Decompress gzip data using Java's native GZIPInputStream
     */
    private fun decompressGzip(sourceFile: File): ByteArray {
        val outputStream = ByteArrayOutputStream()

        GZIPInputStream(BufferedInputStream(FileInputStream(sourceFile))).use { gzip ->
            val buffer = ByteArray(8192)
            var len: Int
            while (gzip.read(buffer).also { len = it } != -1) {
                outputStream.write(buffer, 0, len)
            }
        }

        return outputStream.toByteArray()
    }

    // MARK: - ZIP Extraction

    /**
     * Extract a zip archive using Java's native ZipInputStream
     */
    private fun extractZip(
        sourceFile: File,
        destinationDir: File,
        progressHandler: ((Double) -> Unit)?
    ) {
        Log.i(TAG, "Extracting zip: ${sourceFile.name}")
        progressHandler?.invoke(0.0)

        destinationDir.mkdirs()

        var fileCount = 0
        ZipInputStream(BufferedInputStream(FileInputStream(sourceFile))).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val fileName = entry.name
                val newFile = File(destinationDir, fileName)

                // Security check - prevent zip slip attack
                val destDirPath = destinationDir.canonicalPath
                val newFilePath = newFile.canonicalPath
                if (!newFilePath.startsWith(destDirPath + File.separator)) {
                    throw Exception("Entry is outside of the target dir: $fileName")
                }

                if (entry.isDirectory) {
                    newFile.mkdirs()
                } else {
                    // Create parent directories
                    newFile.parentFile?.mkdirs()

                    // Write file
                    FileOutputStream(newFile).use { fos ->
                        val buffer = ByteArray(8192)
                        var len: Int
                        while (zis.read(buffer).also { len = it } != -1) {
                            fos.write(buffer, 0, len)
                        }
                    }
                    fileCount++
                }

                zis.closeEntry()
                entry = zis.nextEntry
            }
        }

        Log.i(TAG, "Extracted $fileCount files from zip")
        progressHandler?.invoke(1.0)
    }

    // MARK: - TAR Extraction (Pure Kotlin)

    /**
     * Extract tar data to destination directory
     */
    private fun extractTarData(
        tarData: ByteArray,
        destinationDir: File,
        progressHandler: ((Double) -> Unit)?
    ) {
        destinationDir.mkdirs()

        var offset = 0
        val totalSize = tarData.size
        var fileCount = 0

        while (offset + TAR_BLOCK_SIZE <= tarData.size) {
            // Read tar header (512 bytes)
            val headerData = tarData.copyOfRange(offset, offset + TAR_BLOCK_SIZE)

            // Check for end of archive (all zeros)
            if (headerData.all { it.toInt() == 0 }) {
                break
            }

            // Parse header
            val name = extractNullTerminatedString(headerData, 0, 100)
            val sizeStr = extractNullTerminatedString(headerData, 124, 12).trim()
            val typeFlag = headerData[156]
            val prefix = extractNullTerminatedString(headerData, 345, 155)

            // Get full name
            val fullName = if (prefix.isEmpty()) name else "$prefix/$name"

            // Skip if name is empty or is macOS resource fork
            if (fullName.isEmpty() || fullName.startsWith("._")) {
                offset += TAR_BLOCK_SIZE
                continue
            }

            // Parse file size (octal)
            val fileSize = sizeStr.toIntOrNull(8) ?: 0

            offset += TAR_BLOCK_SIZE // Move past header

            val file = File(destinationDir, fullName)

            // Handle different entry types
            when {
                typeFlag.toInt() == 0x35 || (typeFlag.toInt() == 0x30 && fullName.endsWith("/")) -> {
                    // Directory
                    file.mkdirs()
                }
                typeFlag.toInt() == 0x30 || typeFlag.toInt() == 0 -> {
                    // Regular file
                    file.parentFile?.mkdirs()

                    if (fileSize > 0 && offset + fileSize <= tarData.size) {
                        val fileData = tarData.copyOfRange(offset, offset + fileSize)
                        FileOutputStream(file).use { fos ->
                            fos.write(fileData)
                        }
                    } else {
                        file.createNewFile()
                    }
                    fileCount++
                }
                // Skip symbolic links and other types on Android
            }

            // Move to next entry (file data + padding to 512-byte boundary)
            offset += fileSize
            val padding = (TAR_BLOCK_SIZE - (fileSize % TAR_BLOCK_SIZE)) % TAR_BLOCK_SIZE
            offset += padding

            // Report progress
            progressHandler?.invoke(offset.toDouble() / totalSize.toDouble())
        }

        Log.i(TAG, "Extracted $fileCount files from tar")
    }

    // MARK: - Helpers

    private fun extractNullTerminatedString(data: ByteArray, start: Int, maxLength: Int): String {
        val end = minOf(start + maxLength, data.size)
        var nullIndex = end
        for (i in start until end) {
            if (data[i].toInt() == 0) {
                nullIndex = i
                break
            }
        }
        return String(data, start, nullIndex - start, Charsets.UTF_8)
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            else -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
        }
    }
}
