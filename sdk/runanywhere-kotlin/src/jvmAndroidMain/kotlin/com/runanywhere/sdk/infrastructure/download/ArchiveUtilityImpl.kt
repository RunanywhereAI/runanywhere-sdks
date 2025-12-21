package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.*
import java.util.zip.GZIPInputStream
import java.util.zip.ZipInputStream

private val logger = SDKLogger("ArchiveUtilityImpl")

/**
 * Extract tar.bz2 archive
 *
 * Note: BZip2 is not natively supported in Java. For full BZip2 support,
 * applications should add Apache Commons Compress as a dependency.
 * This implementation provides a fallback that throws a helpful error.
 */
internal actual suspend fun extractTarBz2Impl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
): Unit = withContext(Dispatchers.IO) {
    logger.info("Extracting tar.bz2 archive")
    progressHandler?.invoke(0.05)

    // Try to use Apache Commons Compress if available via reflection
    try {
        val bzip2Class = Class.forName("org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream")
        val tarClass = Class.forName("org.apache.commons.compress.archivers.tar.TarArchiveInputStream")

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                val bzip2Constructor = bzip2Class.getConstructor(InputStream::class.java)
                val bzip2In = bzip2Constructor.newInstance(bufferedIn) as InputStream

                bzip2In.use { bz2Stream ->
                    val tarConstructor = tarClass.getConstructor(InputStream::class.java)
                    val tarIn = tarConstructor.newInstance(bz2Stream)

                    (tarIn as Closeable).use {
                        extractTarEntriesViaReflection(tarIn, tarClass, File(destinationPath), progressHandler)
                    }
                }
            }
        }
        logger.info("tar.bz2 extraction completed using Apache Commons Compress")
    } catch (e: ClassNotFoundException) {
        // Fallback: Try using system tar command if available (for JVM on systems with tar)
        logger.debug("Apache Commons Compress not available, trying system tar command")
        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        try {
            val process = ProcessBuilder("tar", "-xjf", sourcePath, "-C", destinationPath)
                .redirectErrorStream(true)
                .start()
            val exitCode = process.waitFor()
            if (exitCode == 0) {
                logger.info("tar.bz2 extraction completed using system tar")
                progressHandler?.invoke(1.0)
                return@withContext
            }
        } catch (processError: Exception) {
            logger.debug("System tar not available: ${processError.message}")
        }

        throw ArchiveExtractionException(
            "BZip2 extraction requires Apache Commons Compress library. " +
            "Add 'org.apache.commons:commons-compress:1.26.0' to your dependencies, " +
            "or use tar.gz format instead."
        )
    }
}

/**
 * Extract tar.gz archive using Java's built-in GZIPInputStream
 */
internal actual suspend fun extractTarGzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
): Unit = withContext(Dispatchers.IO) {
    logger.info("Extracting tar.gz using Java GZIPInputStream")
    progressHandler?.invoke(0.05)

    val destDir = File(destinationPath)
    if (!destDir.exists()) {
        destDir.mkdirs()
    }

    // First, try Apache Commons Compress if available (better tar support)
    try {
        val gzipClass = Class.forName("org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream")
        val tarClass = Class.forName("org.apache.commons.compress.archivers.tar.TarArchiveInputStream")

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                val gzipConstructor = gzipClass.getConstructor(InputStream::class.java)
                val gzipIn = gzipConstructor.newInstance(bufferedIn) as InputStream

                gzipIn.use { gzStream ->
                    val tarConstructor = tarClass.getConstructor(InputStream::class.java)
                    val tarIn = tarConstructor.newInstance(gzStream)

                    (tarIn as Closeable).use {
                        extractTarEntriesViaReflection(tarIn, tarClass, destDir, progressHandler)
                    }
                }
            }
        }
        logger.info("tar.gz extraction completed using Apache Commons Compress")
        return@withContext
    } catch (e: ClassNotFoundException) {
        logger.debug("Apache Commons Compress not available, using fallback")
    }

    // Fallback: Use Java's GZIPInputStream and simple tar parsing
    FileInputStream(sourcePath).use { fileIn ->
        BufferedInputStream(fileIn).use { bufferedIn ->
            GZIPInputStream(bufferedIn).use { gzIn ->
                extractSimpleTar(gzIn, destDir, progressHandler)
            }
        }
    }
    logger.info("tar.gz extraction completed")
}

/**
 * Extract tar.xz archive
 *
 * Note: XZ/LZMA is not natively supported in Java. For full XZ support,
 * applications should add Apache Commons Compress as a dependency.
 */
internal actual suspend fun extractTarXzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
): Unit = withContext(Dispatchers.IO) {
    logger.info("Extracting tar.xz archive")
    progressHandler?.invoke(0.05)

    // Try to use Apache Commons Compress if available via reflection
    try {
        val xzClass = Class.forName("org.apache.commons.compress.compressors.xz.XZCompressorInputStream")
        val tarClass = Class.forName("org.apache.commons.compress.archivers.tar.TarArchiveInputStream")

        FileInputStream(sourcePath).use { fileIn ->
            BufferedInputStream(fileIn).use { bufferedIn ->
                val xzConstructor = xzClass.getConstructor(InputStream::class.java)
                val xzIn = xzConstructor.newInstance(bufferedIn) as InputStream

                xzIn.use { xzStream ->
                    val tarConstructor = tarClass.getConstructor(InputStream::class.java)
                    val tarIn = tarConstructor.newInstance(xzStream)

                    (tarIn as Closeable).use {
                        extractTarEntriesViaReflection(tarIn, tarClass, File(destinationPath), progressHandler)
                    }
                }
            }
        }
        logger.info("tar.xz extraction completed using Apache Commons Compress")
    } catch (e: ClassNotFoundException) {
        // Fallback: Try using system tar command
        logger.debug("Apache Commons Compress not available, trying system tar command")
        val destDir = File(destinationPath)
        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        try {
            val process = ProcessBuilder("tar", "-xJf", sourcePath, "-C", destinationPath)
                .redirectErrorStream(true)
                .start()
            val exitCode = process.waitFor()
            if (exitCode == 0) {
                logger.info("tar.xz extraction completed using system tar")
                progressHandler?.invoke(1.0)
                return@withContext
            }
        } catch (processError: Exception) {
            logger.debug("System tar not available: ${processError.message}")
        }

        throw ArchiveExtractionException(
            "XZ extraction requires Apache Commons Compress library. " +
            "Add 'org.apache.commons:commons-compress:1.26.0' to your dependencies, " +
            "or use tar.gz format instead."
        )
    }
}

/**
 * Extract zip archive using Java's built-in ZipInputStream
 */
internal actual suspend fun extractZipImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
): Unit = withContext(Dispatchers.IO) {
    logger.info("Extracting zip archive")
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
            if (entryName.startsWith("__MACOSX") || entryName.contains("/._")) {
                entry = zipIn.nextEntry
                continue
            }

            val outputFile = File(destDir, entryName)

            // Security check: prevent zip slip vulnerability
            val destDirCanonical = destDir.canonicalPath
            val outputFileCanonical = outputFile.canonicalPath
            if (!outputFileCanonical.startsWith(destDirCanonical + File.separator)) {
                throw SecurityException("Zip entry is outside of destination: $entryName")
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
}

/**
 * Extract tar entries using Apache Commons Compress via reflection
 * This allows the code to work whether or not Commons Compress is on the classpath
 */
private fun extractTarEntriesViaReflection(
    tarIn: Any,
    tarClass: Class<*>,
    destDir: File,
    progressHandler: ((Double) -> Unit)?
) {
    val getNextEntry = tarClass.getMethod("getNextTarEntry")
    val canReadEntryData = tarClass.getMethod("canReadEntryData", Class.forName("org.apache.commons.compress.archivers.tar.TarArchiveEntry"))

    val entryClass = Class.forName("org.apache.commons.compress.archivers.tar.TarArchiveEntry")
    val getName = entryClass.getMethod("getName")
    val isDirectory = entryClass.getMethod("isDirectory")
    val isFile = entryClass.getMethod("isFile")
    val isSymbolicLink = entryClass.getMethod("isSymbolicLink")
    val getLinkName = entryClass.getMethod("getLinkName")

    // Collect entries
    val entries = mutableListOf<Pair<Any, ByteArray?>>()

    var entry = getNextEntry.invoke(tarIn)
    while (entry != null) {
        val data = if (!(isDirectory.invoke(entry) as Boolean) && (canReadEntryData.invoke(tarIn, entry) as Boolean)) {
            (tarIn as InputStream).readBytes()
        } else {
            null
        }
        entries.add(entry to data)
        entry = getNextEntry.invoke(tarIn)
    }

    if (entries.isEmpty()) {
        logger.warning("Tar archive appears to be empty")
        return
    }

    var extractedCount = 0

    for ((tarEntry, data) in entries) {
        val entryName = getName.invoke(tarEntry) as String

        // Skip empty names or macOS resource forks
        if (entryName.isEmpty() || entryName.startsWith("._") || entryName.contains("/._")) {
            continue
        }

        val outputFile = File(destDir, entryName)

        // Security check: prevent tar slip vulnerability
        val destDirCanonical = destDir.canonicalPath
        val outputFileCanonical = outputFile.canonicalPath
        if (!outputFileCanonical.startsWith(destDirCanonical + File.separator)) {
            logger.warning("Skipping tar entry outside destination: $entryName")
            continue
        }

        when {
            isDirectory.invoke(tarEntry) as Boolean -> {
                outputFile.mkdirs()
            }
            isFile.invoke(tarEntry) as Boolean -> {
                outputFile.parentFile?.mkdirs()
                if (data != null) {
                    FileOutputStream(outputFile).use { fos ->
                        fos.write(data)
                    }
                }
            }
            isSymbolicLink.invoke(tarEntry) as Boolean -> {
                outputFile.parentFile?.mkdirs()
                try {
                    val linkName = getLinkName.invoke(tarEntry) as String
                    if (linkName.isNotEmpty()) {
                        val linkPath = outputFile.toPath()
                        val targetPath = java.nio.file.Paths.get(linkName)
                        java.nio.file.Files.createSymbolicLink(linkPath, targetPath)
                    }
                } catch (e: Exception) {
                    logger.debug("Could not create symbolic link: ${e.message}")
                }
            }
        }

        extractedCount++
        val progress = 0.1 + (extractedCount.toDouble() / entries.size) * 0.9
        progressHandler?.invoke(progress)
    }

    logger.info("Extracted $extractedCount entries from tar archive")
}

/**
 * Simple tar extraction without Apache Commons Compress
 * Handles basic USTAR format tar files
 */
private fun extractSimpleTar(
    inputStream: InputStream,
    destDir: File,
    progressHandler: ((Double) -> Unit)?
) {
    val buffer = ByteArray(512)
    var extractedCount = 0

    while (true) {
        // Read tar header (512 bytes)
        val headerRead = inputStream.readNBytes(buffer, 0, 512)
        if (headerRead < 512) break

        // Check for end of archive (two zero blocks)
        if (buffer.all { it == 0.toByte() }) {
            // Read next block to confirm end
            val nextRead = inputStream.readNBytes(buffer, 0, 512)
            if (nextRead < 512 || buffer.all { it == 0.toByte() }) {
                break
            }
        }

        // Parse header
        val name = String(buffer, 0, 100).trim('\u0000', ' ')
        if (name.isEmpty()) break

        // Parse size (octal string at offset 124, 12 bytes)
        val sizeStr = String(buffer, 124, 12).trim('\u0000', ' ')
        val size = try {
            if (sizeStr.isEmpty()) 0L else sizeStr.toLong(8)
        } catch (e: NumberFormatException) {
            0L
        }

        // Parse type flag (offset 156)
        val typeFlag = buffer[156].toInt().toChar()

        // Skip macOS resource forks
        if (name.startsWith("._") || name.contains("/._")) {
            // Skip file data
            val blocks = (size + 511) / 512
            inputStream.skip(blocks * 512)
            continue
        }

        val outputFile = File(destDir, name)

        // Security check
        val destDirCanonical = destDir.canonicalPath
        try {
            val outputFileCanonical = outputFile.canonicalPath
            if (!outputFileCanonical.startsWith(destDirCanonical + File.separator) &&
                outputFileCanonical != destDirCanonical) {
                logger.warning("Skipping tar entry outside destination: $name")
                val blocks = (size + 511) / 512
                inputStream.skip(blocks * 512)
                continue
            }
        } catch (e: IOException) {
            val blocks = (size + 511) / 512
            inputStream.skip(blocks * 512)
            continue
        }

        when (typeFlag) {
            '5', 'D' -> { // Directory
                outputFile.mkdirs()
            }
            '0', '\u0000', '7' -> { // Regular file
                outputFile.parentFile?.mkdirs()

                FileOutputStream(outputFile).use { fos ->
                    var remaining = size
                    val readBuffer = ByteArray(8192)
                    while (remaining > 0) {
                        val toRead = minOf(remaining.toInt(), readBuffer.size)
                        val read = inputStream.read(readBuffer, 0, toRead)
                        if (read <= 0) break
                        fos.write(readBuffer, 0, read)
                        remaining -= read
                    }
                }

                // Skip padding to 512-byte boundary
                val padding = (512 - (size % 512)) % 512
                if (padding > 0) {
                    inputStream.skip(padding)
                }

                extractedCount++
            }
            else -> {
                // Skip unsupported entry types
                val blocks = (size + 511) / 512
                inputStream.skip(blocks * 512)
            }
        }

        progressHandler?.invoke(0.1 + 0.9 * (extractedCount.toDouble() / 100).coerceAtMost(0.9))
    }

    logger.info("Extracted $extractedCount files from tar archive")
    progressHandler?.invoke(1.0)
}
