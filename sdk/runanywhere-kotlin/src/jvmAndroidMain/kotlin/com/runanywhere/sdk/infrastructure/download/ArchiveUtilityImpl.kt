package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.Paths
import java.util.zip.ZipInputStream

private val logger = SDKLogger("ArchiveUtilityImpl")

/**
 * Extract tar.bz2 archive using Apache Commons Compress
 */
internal actual suspend fun extractTarBz2Impl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
) {
    withContext(Dispatchers.IO) {
        logger.info("Extracting tar.bz2 archive: $sourcePath")
        progressHandler?.invoke(0.05)

        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                BZip2CompressorInputStream(bufferedIn).use { bz2In ->
                    TarArchiveInputStream(bz2In).use { tarIn ->
                        extractTarEntries(tarIn, destDir, progressHandler)
                    }
                }
            }
        }

        logger.info("tar.bz2 extraction completed")
        progressHandler?.invoke(1.0)
    }
}

/**
 * Extract tar.gz archive using Apache Commons Compress
 */
internal actual suspend fun extractTarGzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
) {
    withContext(Dispatchers.IO) {
        logger.info("Extracting tar.gz archive: $sourcePath")
        progressHandler?.invoke(0.05)

        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                GzipCompressorInputStream(bufferedIn).use { gzIn ->
                    TarArchiveInputStream(gzIn).use { tarIn ->
                        extractTarEntries(tarIn, destDir, progressHandler)
                    }
                }
            }
        }

        logger.info("tar.gz extraction completed")
        progressHandler?.invoke(1.0)
    }
}

/**
 * Extract tar.xz archive using Apache Commons Compress
 */
internal actual suspend fun extractTarXzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
) {
    withContext(Dispatchers.IO) {
        logger.info("Extracting tar.xz archive: $sourcePath")
        progressHandler?.invoke(0.05)

        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                XZCompressorInputStream(bufferedIn).use { xzIn ->
                    TarArchiveInputStream(xzIn).use { tarIn ->
                        extractTarEntries(tarIn, destDir, progressHandler)
                    }
                }
            }
        }

        logger.info("tar.xz extraction completed")
        progressHandler?.invoke(1.0)
    }
}

/**
 * Extract zip archive using Java's built-in ZipInputStream
 */
internal actual suspend fun extractZipImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?,
) {
    withContext(Dispatchers.IO) {
        logger.info("Extracting zip archive: $sourcePath")
        progressHandler?.invoke(0.05)

        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        // First pass: count entries for progress
        var totalEntries = 0
        ZipInputStream(FileInputStream(sourcePath)).use { zipIn ->
            while (zipIn.nextEntry != null) {
                totalEntries++
            }
        }

        if (totalEntries == 0) {
            logger.warning("Zip archive appears to be empty")
            progressHandler?.invoke(1.0)
            return@withContext
        }

        // Second pass: extract entries
        var extractedCount = 0
        ZipInputStream(FileInputStream(sourcePath)).use { zipIn ->
            var entry = zipIn.nextEntry
            while (entry != null) {
                val entryName = entry.name

                // Skip macOS resource fork files
                if (entryName.startsWith("__MACOSX") || entryName.contains("/._") || entryName.startsWith("._")) {
                    entry = zipIn.nextEntry
                    continue
                }

                val outputFile = File(destDir, entryName)

                // Security check: prevent zip slip vulnerability
                val destDirCanonical = destDir.canonicalPath
                val outputFileCanonical = outputFile.canonicalPath
                if (!outputFileCanonical.startsWith(destDirCanonical + File.separator) &&
                    outputFileCanonical != destDirCanonical
                ) {
                    logger.warning("Skipping zip entry outside destination: $entryName")
                    entry = zipIn.nextEntry
                    continue
                }

                if (entry.isDirectory) {
                    outputFile.mkdirs()
                } else {
                    // Create parent directories if needed
                    outputFile.parentFile?.mkdirs()

                    // Write file
                    FileOutputStream(outputFile).use { fos ->
                        val buffer = ByteArray(8192)
                        var len: Int
                        while (zipIn.read(buffer).also { len = it } > 0) {
                            fos.write(buffer, 0, len)
                        }
                    }
                }

                extractedCount++
                val progress = 0.1 + (extractedCount.toDouble() / totalEntries) * 0.9
                progressHandler?.invoke(progress)

                entry = zipIn.nextEntry
            }
        }

        logger.info("Extracted $extractedCount files from zip archive")
        progressHandler?.invoke(1.0)
    }
}

/**
 * Extract tar entries from a TarArchiveInputStream
 * Shared logic for tar.gz, tar.bz2, and tar.xz formats
 */
private fun extractTarEntries(
    tarIn: TarArchiveInputStream,
    destDir: File,
    progressHandler: ((Double) -> Unit)?,
) {
    val destDirCanonical = destDir.canonicalPath
    var extractedCount = 0
    var entry: TarArchiveEntry? = tarIn.nextEntry

    while (entry != null) {
        val entryName = entry.name

        // Skip empty names or macOS resource forks
        if (entryName.isEmpty() || entryName.startsWith("._") || entryName.contains("/._")) {
            entry = tarIn.nextEntry
            continue
        }

        val outputFile = File(destDir, entryName)

        // Security check: prevent tar slip vulnerability
        val outputFileCanonical = outputFile.canonicalPath
        if (!outputFileCanonical.startsWith(destDirCanonical + File.separator) &&
            outputFileCanonical != destDirCanonical
        ) {
            logger.warning("Skipping tar entry outside destination: $entryName")
            entry = tarIn.nextEntry
            continue
        }

        when {
            entry.isDirectory -> {
                outputFile.mkdirs()
            }
            entry.isFile -> {
                outputFile.parentFile?.mkdirs()

                if (tarIn.canReadEntryData(entry)) {
                    FileOutputStream(outputFile).use { fos ->
                        val buffer = ByteArray(8192)
                        var len: Int
                        while (tarIn.read(buffer).also { len = it } > 0) {
                            fos.write(buffer, 0, len)
                        }
                    }
                }
                extractedCount++
            }
            entry.isSymbolicLink -> {
                outputFile.parentFile?.mkdirs()
                try {
                    val linkName = entry.linkName
                    if (linkName.isNotEmpty()) {
                        val linkPath = outputFile.toPath()
                        val targetPath = Paths.get(linkName)
                        // Only create symlink if it doesn't already exist
                        if (!Files.exists(linkPath)) {
                            Files.createSymbolicLink(linkPath, targetPath)
                        }
                    }
                } catch (e: Exception) {
                    logger.debug("Could not create symbolic link for $entryName: ${e.message}")
                }
            }
        }

        // Update progress (estimate based on count, not perfect but better than nothing)
        val progress = 0.1 + (extractedCount.toDouble() / 100).coerceAtMost(0.85)
        progressHandler?.invoke(progress)

        entry = tarIn.nextEntry
    }

    logger.info("Extracted $extractedCount entries from tar archive")
}
