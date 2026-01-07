/**
 * ArchiveUtility.kt
 *
 * Native archive extraction utility for Android.
 * Uses Apache Commons Compress for robust tar.gz extraction (streaming, memory-efficient).
 * Uses Java's native ZipInputStream for zip extraction.
 *
 * Mirrors the implementation from:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift
 *
 * Supports: tar.gz, zip
 */

package com.margelo.nitro.runanywhere

import android.util.Log
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

/**
 * Utility for handling archive extraction on Android
 */
object ArchiveUtility {
    private const val TAG = "ArchiveUtility"

    /**
     * Extract an archive to a destination directory
     * @param archivePath Path to the archive file
     * @param destinationPath Destination directory path
     * @return true if extraction succeeded
     */
    @JvmStatic
    fun extract(archivePath: String, destinationPath: String): Boolean {
        Log.i(TAG, "extract() called: $archivePath -> $destinationPath")
        return try {
            extractArchive(archivePath, destinationPath)
            Log.i(TAG, "extract() succeeded")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Extraction failed: ${e.message}")
            Log.e(TAG, "Stack trace:", e)
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
                // tar.bz2 not commonly used for ML models, recommend tar.gz
                throw Exception("tar.bz2 format not currently supported. Please use tar.gz format.")
            }
            ArchiveType.XZ -> {
                // tar.xz not commonly used for ML models, recommend tar.gz
                throw Exception("tar.xz format not currently supported. Please use tar.gz format.")
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
     * Extract a tar.gz archive using Apache Commons Compress (streaming, memory-efficient)
     * This approach doesn't load the entire file into memory.
     */
    private fun extractTarGz(
        sourceFile: File,
        destinationDir: File,
        progressHandler: ((Double) -> Unit)?
    ) {
        val startTime = System.currentTimeMillis()
        Log.i(TAG, "Extracting tar.gz: ${sourceFile.name} (size: ${formatBytes(sourceFile.length())})")
        progressHandler?.invoke(0.0)

        destinationDir.mkdirs()
        var fileCount = 0
        val totalSize = sourceFile.length()
        var bytesRead = 0L

        try {
            // Use Apache Commons Compress for streaming tar.gz extraction
            FileInputStream(sourceFile).use { fis ->
                BufferedInputStream(fis).use { bis ->
                    GzipCompressorInputStream(bis).use { gzis ->
                        TarArchiveInputStream(gzis).use { tarIn ->
                            var entry: TarArchiveEntry? = tarIn.nextTarEntry
                            while (entry != null) {
                                val name = entry.name

                                // Skip macOS resource forks and empty names
                                if (name.isEmpty() || name.startsWith("._") || name.startsWith("./._")) {
                                    entry = tarIn.nextTarEntry
                                    continue
                                }

                                val outputFile = File(destinationDir, name)

                                // Security check - prevent zip slip attack
                                val destDirPath = destinationDir.canonicalPath
                                val outputFilePath = outputFile.canonicalPath
                                if (!outputFilePath.startsWith(destDirPath + File.separator) &&
                                    outputFilePath != destDirPath) {
                                    Log.w(TAG, "Skipping entry outside destination: $name")
                                    entry = tarIn.nextTarEntry
                                    continue
                                }

                                if (entry.isDirectory) {
                                    outputFile.mkdirs()
                                } else {
                                    // Create parent directories
                                    outputFile.parentFile?.mkdirs()

                                    // Extract file
                                    FileOutputStream(outputFile).use { fos ->
                                        val buffer = ByteArray(8192)
                                        var len: Int
                                        while (tarIn.read(buffer).also { len = it } != -1) {
                                            fos.write(buffer, 0, len)
                                            bytesRead += len
                                        }
                                    }
                                    fileCount++

                                    // Log progress for large files
                                    if (fileCount % 10 == 0) {
                                        Log.d(TAG, "Extracted $fileCount files...")
                                    }
                                }

                                // Report progress (estimate based on compressed bytes)
                                val progress = (bytesRead.toDouble() / (totalSize * 3)).coerceAtMost(0.95)
                                progressHandler?.invoke(progress)

                                entry = tarIn.nextTarEntry
                            }
                        }
                    }
                }
            }

            val totalTime = System.currentTimeMillis() - startTime
            Log.i(TAG, "Extracted $fileCount files in ${totalTime}ms")
            progressHandler?.invoke(1.0)
        } catch (e: Exception) {
            Log.e(TAG, "tar.gz extraction failed: ${e.message}", e)
            throw e
        }
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

    // MARK: - Helpers

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            else -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
        }
    }
}
