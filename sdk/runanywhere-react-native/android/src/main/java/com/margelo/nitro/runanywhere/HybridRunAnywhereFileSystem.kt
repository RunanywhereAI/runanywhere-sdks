/**
 * HybridRunAnywhereFileSystem.kt
 *
 * Android implementation of file system operations for RunAnywhere SDK.
 * Provides model management, file I/O, and disk space utilities.
 */

package com.margelo.nitro.runanywhere

import android.os.StatFs
import android.util.Log
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
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
        private const val BUFFER_SIZE = 256 * 1024
    }

    private val context = NitroModules.applicationContext ?: error("Android context not found")

    /**
     * Get the RunAnywhere data directory path
     */
    override fun getDataDirectory(): Promise<String> = Promise.async {
        runanywhereFile().absolutePath
    }

    /**
     * Get the models directory path
     */
    override fun getModelsDirectory(): Promise<String> = Promise.async {
        val modelsDir = File(runanywhereFile(), MODELS_DIR_NAME)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
        modelsDir.absolutePath
    }

    /**
     * Check if a file exists
     */
    override fun fileExists(path: String): Promise<Boolean> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        file.exists()
    }

    /**
     * Check if a model exists
     */
    override fun modelExists(modelId: String): Promise<Boolean> = Promise.async {
        modelFile(modelId).exists()
    }

    /**
     * Get the full path to a model
     */
    override fun getModelPath(modelId: String): Promise<String> = Promise.async {
        modelFile(modelId).absolutePath
    }

    /**
     * Download a model from URL with progress callback
     */
    override fun downloadModel(
        modelId: String,
        url: String,
        callback: ((progress: Double) -> Unit)?
    ): Promise<Unit> {
        return Promise.async {
            val modelFile = modelFile(modelId)

            if (modelFile.exists()) {
                callback?.invoke(1.0)
                return@async
            }

            val downloadUrl = try {
                URL(url)
            } catch (_: Throwable) {
                throw Error("Invalid URL")
            }

            val tmpFile = File.createTempFile("dl_", ".tmp", context.cacheDir)
            var connection: HttpURLConnection? = null

            try {
                connection = (downloadUrl.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 30_000
                    readTimeout = 5 * 60_000
                    instanceFollowRedirects = true
                }
                connection.connect()
                val code = connection.responseCode

                if (code !in 200..299) {
                    connection.disconnect()
                    throw Error("Download failed with HTTP status code: $code")
                }

                val contentLength = connection.getHeaderFieldLong("Content-Length", -1L)
                var downloaded = 0L
                var lastPct = -1.0

                callback?.invoke(0.0)

                connection.inputStream.use { input ->
                    FileOutputStream(tmpFile).use { output ->
                        val buf = ByteArray(BUFFER_SIZE)

                        while (true) {
                            val read = input.read(buf)
                            if (read == -1) break

                            output.write(buf, 0, read)
                            downloaded += read

                            if (contentLength > 0) {
                                val pct = floor(
                                    (downloaded.toDouble() / contentLength.toDouble())
                                        .coerceIn(0.0, 1.0) * 99
                                ) / 100.0

                                if (pct - lastPct >= 0.01) {
                                    callback?.invoke(pct)
                                    lastPct = pct
                                }
                            }
                        }
                    }
                }

                // Move temp file to final location
                modelFile.parentFile?.mkdirs()
                tmpFile.renameTo(modelFile)

                Log.i(TAG, "Download complete: $modelId (${modelFile.length()} bytes)")
                callback?.invoke(1.0)

            } catch (t: Throwable) {
                modelFile.delete()
                throw Error("Failed to download model: ${t.message}")
            } finally {
                tmpFile.delete()
                connection?.disconnect()
            }
        }
    }

    /**
     * Delete a downloaded model
     */
    override fun deleteModel(modelId: String): Promise<Unit> = Promise.async {
        val modelFile = modelFile(modelId)

        if (!modelFile.exists()) {
            throw Error("No such model: $modelId")
        }

        modelFile.deleteRecursively()
    }

    /**
     * Read a text file
     */
    override fun readFile(path: String): Promise<String> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)

        if (!file.exists()) {
            throw Error("No such file: $path")
        }

        file.readText()
    }

    /**
     * Write a text file
     */
    override fun writeFile(path: String, content: String): Promise<Unit> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)
        file.parentFile?.mkdirs()
        file.writeText(content)
    }

    /**
     * Delete a file
     */
    override fun deleteFile(path: String): Promise<Unit> = Promise.async {
        val runanywhereDir = runanywhereFile()
        val file = File(runanywhereDir, path)

        if (!file.exists()) {
            throw Error("No such file: $path")
        }

        file.deleteRecursively()
    }

    /**
     * Get available disk space in bytes
     */
    override fun getAvailableDiskSpace(): Promise<Double> = Promise.async {
        val stat = StatFs(context.filesDir.absolutePath)
        stat.availableBytes.toDouble()
    }

    /**
     * Get total disk space in bytes
     */
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
        return File(modelsDir, modelId)
    }
}
