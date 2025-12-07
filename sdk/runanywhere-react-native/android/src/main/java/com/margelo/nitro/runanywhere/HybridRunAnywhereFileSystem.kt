/**
 * HybridRunAnywhereFileSystem.kt
 *
 * Android implementation of file system operations for RunAnywhere SDK.
 * Uses the same simple approach as runanywhere-kotlin for fast downloads.
 */

package com.margelo.nitro.runanywhere

import android.os.StatFs
import android.util.Log
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.floor

/**
 * Kotlin implementation of RunAnywhereFileSystem HybridObject.
 * Uses same download strategy as runanywhere-kotlin SDK for consistent speed.
 */
class HybridRunAnywhereFileSystem : HybridRunAnywhereFileSystemSpec() {

    companion object {
        private const val TAG = "HybridRunAnywhereFS"
        private const val DATA_DIR_NAME = "runanywhere"
        private const val MODELS_DIR_NAME = "models"
        private const val BUFFER_SIZE = 8192 // 8KB - same as Kotlin SDK
        private const val MAX_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
    }

    private val context = NitroModules.applicationContext ?: error("Android context not found")

    override fun getDataDirectory(): Promise<String> = Promise.async {
        runanywhereFile().absolutePath
    }

    override fun getModelsDirectory(): Promise<String> = Promise.async {
        val modelsDir = File(runanywhereFile(), MODELS_DIR_NAME)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
        modelsDir.absolutePath
    }

    override fun fileExists(path: String): Promise<Boolean> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        file.exists()
    }

    override fun modelExists(modelId: String): Promise<Boolean> = Promise.async {
        modelFile(modelId).exists()
    }

    override fun getModelPath(modelId: String): Promise<String> = Promise.async {
        modelFile(modelId).absolutePath
    }

    /**
     * Download a model with resume support and retry logic.
     * Handles network interruptions gracefully.
     */
    override fun downloadModel(
        modelId: String,
        url: String,
        callback: ((progress: Double) -> Unit)?
    ): Promise<Unit> {
        return Promise.async {
            val modelFile = modelFile(modelId)

            if (modelFile.exists()) {
                Log.i(TAG, "Model already exists: $modelId")
                
                // If it's an archive that hasn't been extracted yet, extract it now
                if (isArchive(modelId)) {
                    val archiveName = modelFile.nameWithoutExtension.removeSuffix(".tar")
                    val extractDir = File(modelFile.parentFile, "sherpa-models/$archiveName")
                    if (!extractDir.exists()) {
                        Log.i(TAG, "Archive exists but not extracted, extracting now...")
                        extractArchive(modelFile)
                    } else {
                        Log.i(TAG, "Archive already extracted to: ${extractDir.absolutePath}")
                    }
                }
                
                callback?.invoke(1.0)
                return@async
            }

            // Ensure parent directory exists
            modelFile.parentFile?.mkdirs()

            // Use temp file for resume support
            val tempPath = "${modelFile.absolutePath}.tmp"
            val tempFile = File(tempPath)

            var lastException: Exception? = null
            var attempt = 0

            while (attempt < MAX_RETRIES) {
                attempt++
                var urlConnection: HttpURLConnection? = null

                try {
                    // Check how much we've already downloaded
                    val existingBytes = if (tempFile.exists()) tempFile.length() else 0L

                    Log.i(TAG, "Download attempt $attempt/$MAX_RETRIES for $modelId (resuming from $existingBytes bytes)")
                    
                    urlConnection = URL(url).openConnection() as HttpURLConnection
                    urlConnection.requestMethod = "GET"
                    urlConnection.connectTimeout = 30000
                    urlConnection.readTimeout = 60000 // Increased to 60s for slow connections

                    // Add Range header for resume
                    if (existingBytes > 0) {
                        urlConnection.setRequestProperty("Range", "bytes=$existingBytes-")
                        Log.i(TAG, "Resuming download from byte $existingBytes")
                    }

                    urlConnection.connect()

                    val responseCode = urlConnection.responseCode
                    
                    // 206 = Partial Content (resume), 200 = OK (fresh start)
                    if (responseCode != HttpURLConnection.HTTP_OK && 
                        responseCode != HttpURLConnection.HTTP_PARTIAL) {
                        throw Exception("HTTP error: $responseCode")
                    }

                    // Get total size
                    val contentLength = urlConnection.contentLengthLong
                    val totalBytes = if (responseCode == HttpURLConnection.HTTP_PARTIAL) {
                        // Parse Content-Range header for total size
                        val contentRange = urlConnection.getHeaderField("Content-Range")
                        if (contentRange != null && contentRange.contains("/")) {
                            contentRange.substringAfter("/").toLongOrNull() ?: (existingBytes + contentLength)
                        } else {
                            existingBytes + contentLength
                        }
                    } else {
                        // Fresh download - delete any partial file
                        if (tempFile.exists()) tempFile.delete()
                        contentLength
                    }

                    Log.i(TAG, "Total size: $totalBytes bytes (${totalBytes / (1024 * 1024)}MB)")

                    val startTime = System.currentTimeMillis()
                    val startBytes = if (tempFile.exists()) tempFile.length() else 0L

                    // Append if resuming, otherwise create new
                    FileOutputStream(tempFile, responseCode == HttpURLConnection.HTTP_PARTIAL).use { output ->
                        urlConnection.inputStream.use { input ->
                            val buffer = ByteArray(BUFFER_SIZE)
                            var bytesDownloaded = startBytes
                            var bytesRead: Int
                            var lastReportTime = System.currentTimeMillis()
                            var lastPct = -1.0

                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                output.write(buffer, 0, bytesRead)
                                bytesDownloaded += bytesRead

                                // Report progress every 300ms
                                val currentTime = System.currentTimeMillis()
                                if (currentTime - lastReportTime >= 300) {
                                    if (totalBytes > 0) {
                                        val pct = floor(
                                            (bytesDownloaded.toDouble() / totalBytes.toDouble())
                                                .coerceIn(0.0, 1.0) * 99
                                        ) / 100.0

                                        if (pct - lastPct >= 0.01) {
                                            val elapsed = (currentTime - startTime) / 1000.0
                                            val downloadedThisSession = bytesDownloaded - startBytes
                                            val speedMBps = if (elapsed > 0) (downloadedThisSession / 1024.0 / 1024.0) / elapsed else 0.0
                                            Log.d(TAG, "Progress: ${(pct * 100).toInt()}% @ ${String.format("%.2f", speedMBps)} MB/s")
                                            
                                            callback?.invoke(pct)
                                            lastPct = pct
                                        }
                                    }
                                    lastReportTime = currentTime
                                }
                            }

                            Log.i(TAG, "Download stream completed: $bytesDownloaded bytes")
                        }
                    }

                    // Verify download size
                    val downloadedSize = tempFile.length()
                    if (totalBytes > 0 && downloadedSize < totalBytes) {
                        throw Exception("Incomplete download: got $downloadedSize of $totalBytes bytes")
                    }

                    // Atomic move to final destination
                    if (modelFile.exists()) {
                        modelFile.delete()
                    }
                    if (!tempFile.renameTo(modelFile)) {
                        throw Exception("Failed to rename temp file to final destination")
                    }

                    val duration = (System.currentTimeMillis() - startTime) / 1000.0
                    val sizeMB = modelFile.length() / (1024.0 * 1024.0)
                    val speedMBps = if (duration > 0) sizeMB / duration else 0.0

                    Log.i(TAG, "Download complete: $modelId (${String.format("%.1f", sizeMB)}MB in ${String.format("%.1f", duration)}s = ${String.format("%.2f", speedMBps)}MB/s)")
                    
                    // Auto-extract archives (Android fallback since libarchive not linked in pre-built binaries)
                    if (isArchive(modelId)) {
                        Log.i(TAG, "Extracting archive: $modelId")
                        extractArchive(modelFile)
                    }
                    
                    callback?.invoke(1.0)
                    return@async // Success!

                } catch (e: Exception) {
                    Log.w(TAG, "Download attempt $attempt failed: ${e.message}")
                    lastException = e

                    if (attempt < MAX_RETRIES) {
                        Log.i(TAG, "Retrying in ${RETRY_DELAY_MS}ms...")
                        Thread.sleep(RETRY_DELAY_MS)
                    }
                } finally {
                    urlConnection?.disconnect()
                }
            }

            // All retries failed
            Log.e(TAG, "Download failed after $MAX_RETRIES attempts", lastException)
            throw Error("Download failed after $MAX_RETRIES attempts: ${lastException?.message}")
        }
    }

    override fun deleteModel(modelId: String): Promise<Unit> = Promise.async {
        val modelFile = modelFile(modelId)
        if (!modelFile.exists()) {
            throw Error("No such model: $modelId")
        }
        modelFile.deleteRecursively()
    }

    override fun readFile(path: String): Promise<String> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        if (!file.exists()) {
            throw Error("No such file: $path")
        }
        file.readText()
    }

    override fun writeFile(path: String, content: String): Promise<Unit> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        file.parentFile?.mkdirs()
        file.writeText(content)
    }

    override fun deleteFile(path: String): Promise<Unit> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        if (!file.exists()) {
            throw Error("No such file: $path")
        }
        file.deleteRecursively()
    }

    override fun getAvailableDiskSpace(): Promise<Double> = Promise.async {
        val stat = StatFs(context.filesDir.absolutePath)
        stat.availableBytes.toDouble()
    }

    override fun getTotalDiskSpace(): Promise<Double> = Promise.async {
        val stat = StatFs(context.filesDir.absolutePath)
        stat.totalBytes.toDouble()
    }

    private fun runanywhereFile(): File {
        val runanywhereDir = File(context.filesDir, DATA_DIR_NAME)
        if (!runanywhereDir.exists()) {
            runanywhereDir.mkdirs()
        }
        return runanywhereDir
    }

    private fun modelFile(modelId: String): File {
        val modelsDir = File(runanywhereFile(), MODELS_DIR_NAME)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
        return File(modelsDir, modelId)
    }

    // ==========================================================================
    // Archive Extraction (Kotlin fallback - same as runanywhere-kotlin SDK)
    // Android pre-built binaries don't have libarchive, so we use Apache Commons
    // ==========================================================================

    private fun isArchive(fileName: String): Boolean {
        return fileName.endsWith(".tar.bz2") || 
               fileName.endsWith(".tar.gz") || 
               fileName.endsWith(".tgz")
    }

    /**
     * Extract archive using Apache Commons Compress
     * Same implementation as runanywhere-kotlin SDK
     */
    private fun extractArchive(archiveFile: File) {
        val archiveName = archiveFile.nameWithoutExtension.removeSuffix(".tar")
        val extractDir = File(archiveFile.parentFile, "sherpa-models/$archiveName")
        
        if (extractDir.exists()) {
            Log.i(TAG, "Archive already extracted: ${extractDir.absolutePath}")
            return
        }
        
        extractDir.mkdirs()
        Log.i(TAG, "Extracting ${archiveFile.name} to ${extractDir.absolutePath}")
        
        val startTime = System.currentTimeMillis()
        var fileCount = 0
        
        try {
            when {
                archiveFile.name.endsWith(".tar.bz2") -> {
                    FileInputStream(archiveFile).use { fileIn ->
                        BufferedInputStream(fileIn, BUFFER_SIZE).use { bufferedIn ->
                            BZip2CompressorInputStream(bufferedIn).use { bz2In ->
                                TarArchiveInputStream(bz2In).use { tarIn ->
                                    fileCount = extractTarEntries(tarIn, extractDir)
                                }
                            }
                        }
                    }
                }
                archiveFile.name.endsWith(".tar.gz") || archiveFile.name.endsWith(".tgz") -> {
                    FileInputStream(archiveFile).use { fileIn ->
                        BufferedInputStream(fileIn, BUFFER_SIZE).use { bufferedIn ->
                            GzipCompressorInputStream(bufferedIn).use { gzIn ->
                                TarArchiveInputStream(gzIn).use { tarIn ->
                                    fileCount = extractTarEntries(tarIn, extractDir)
                                }
                            }
                        }
                    }
                }
                else -> throw Error("Unsupported archive format: ${archiveFile.name}")
            }
            
            val duration = (System.currentTimeMillis() - startTime) / 1000.0
            Log.i(TAG, "Extracted $fileCount files in ${String.format("%.1f", duration)}s")
            
            // Delete archive after successful extraction to save space
            archiveFile.delete()
            Log.i(TAG, "Deleted archive: ${archiveFile.name}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Extraction failed: ${e.message}", e)
            extractDir.deleteRecursively()
            throw Error("Archive extraction failed: ${e.message}")
        }
    }

    private fun extractTarEntries(tarIn: TarArchiveInputStream, destDir: File): Int {
        var entry: TarArchiveEntry?
        var count = 0
        val buffer = ByteArray(BUFFER_SIZE)
        
        while (tarIn.nextEntry.also { entry = it } != null) {
            val currentEntry = entry ?: continue
            val outputFile = File(destDir, currentEntry.name)
            
            if (currentEntry.isDirectory) {
                outputFile.mkdirs()
            } else {
                outputFile.parentFile?.mkdirs()
                
                FileOutputStream(outputFile).use { output ->
                    var bytesRead: Int
                    while (tarIn.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                }
                count++
            }
        }
        
        return count
    }
}
