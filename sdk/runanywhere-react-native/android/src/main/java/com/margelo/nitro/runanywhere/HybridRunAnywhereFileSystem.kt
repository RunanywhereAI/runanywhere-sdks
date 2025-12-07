/**
 * HybridRunAnywhereFileSystem.kt
 *
 * Android implementation of file system operations for RunAnywhere SDK.
 * Uses OkHttp for maximum download speed (bypasses RN bridge).
 */

package com.margelo.nitro.runanywhere

import android.os.StatFs
import android.util.Log
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.floor

/**
 * Kotlin implementation of RunAnywhereFileSystem HybridObject.
 * Handles all file system operations for the RunAnywhere SDK on Android.
 */
class HybridRunAnywhereFileSystem : HybridRunAnywhereFileSystemSpec() {

    companion object {
        private const val TAG = "HybridRunAnywhereFS"
        private const val DATA_DIR_NAME = "runanywhere"
        private const val MODELS_DIR_NAME = "models"
        private const val BUFFER_SIZE = 8 * 1024 * 1024 // 8MB buffer - very large for max throughput
        
        // Shared OkHttp client optimized for large file downloads
        private val httpClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.MINUTES)
                .writeTimeout(10, TimeUnit.MINUTES)
                .followRedirects(true)
                .followSslRedirects(true)
                .retryOnConnectionFailure(true)
                .build()
        }
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
     * Download a model using OkHttp (bypasses React Native bridge for maximum speed).
     * Uses 8MB buffer for maximum throughput.
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
                callback?.invoke(1.0)
                return@async
            }

            // Ensure parent directory exists
            modelFile.parentFile?.mkdirs()

            // Use temp file for atomic write
            val tmpFile = File(modelFile.parentFile, "${modelId}.tmp")
            tmpFile.delete() // Clean up any previous partial download
            
            val startTime = System.currentTimeMillis()
            Log.i(TAG, "Starting OkHttp download: $modelId from $url")
            callback?.invoke(0.0)

            try {
                val request = Request.Builder()
                    .url(url)
                    .header("Accept", "*/*")
                    .header("User-Agent", "RunAnywhere-Android/1.0")
                    .build()

                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        throw Error("Download failed with HTTP ${response.code}")
                    }

                    val body = response.body ?: throw Error("Empty response body")
                    val contentLength = body.contentLength()
                    var downloaded = 0L
                    var lastPct = -1.0
                    var lastLogTime = startTime

                    Log.i(TAG, "Content-Length: $contentLength bytes (${contentLength / (1024 * 1024)}MB)")

                    // Use BufferedInputStream/BufferedOutputStream with large buffer
                    BufferedInputStream(body.byteStream(), BUFFER_SIZE).use { input ->
                        BufferedOutputStream(FileOutputStream(tmpFile), BUFFER_SIZE).use { output ->
                            val buffer = ByteArray(BUFFER_SIZE)
                            
                            while (true) {
                                val bytesRead = input.read(buffer)
                                if (bytesRead == -1) break

                                output.write(buffer, 0, bytesRead)
                                downloaded += bytesRead

                                if (contentLength > 0) {
                                    val pct = floor(
                                        (downloaded.toDouble() / contentLength.toDouble())
                                            .coerceIn(0.0, 1.0) * 99
                                    ) / 100.0

                                    // Report every 1% and log speed every 5 seconds
                                    if (pct - lastPct >= 0.01) {
                                        callback?.invoke(pct)
                                        lastPct = pct
                                        
                                        val now = System.currentTimeMillis()
                                        if (now - lastLogTime >= 5000) {
                                            val elapsed = (now - startTime) / 1000.0
                                            val speed = if (elapsed > 0) (downloaded / 1024.0 / 1024.0) / elapsed else 0.0
                                            Log.i(TAG, "Progress: ${(pct * 100).toInt()}% @ ${String.format("%.2f", speed)} MB/s")
                                            lastLogTime = now
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Atomic rename from temp to final
                if (tmpFile.exists()) {
                    if (modelFile.exists()) modelFile.delete()
                    tmpFile.renameTo(modelFile)
                }

                val duration = (System.currentTimeMillis() - startTime) / 1000.0
                val sizeMB = modelFile.length() / (1024.0 * 1024.0)
                val speedMBps = if (duration > 0) sizeMB / duration else 0.0

                Log.i(TAG, "Download complete: $modelId (${String.format("%.1f", sizeMB)}MB in ${String.format("%.1f", duration)}s = ${String.format("%.2f", speedMBps)}MB/s)")
                callback?.invoke(1.0)

            } catch (t: Throwable) {
                Log.e(TAG, "Download failed: ${t.message}", t)
                tmpFile.delete()
                modelFile.delete()
                throw Error("Download failed: ${t.message}")
            }
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
}
