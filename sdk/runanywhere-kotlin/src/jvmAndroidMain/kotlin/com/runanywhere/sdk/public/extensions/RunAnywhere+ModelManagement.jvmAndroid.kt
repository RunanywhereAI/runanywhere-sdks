/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for model management operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

// MARK: - Model Registration Implementation

private val registrationLogger = SDKLogger("RunAnywhere.Models")

/**
 * Internal implementation for registering a model to the C++ registry.
 * This is called by the public registerModel() function in commonMain.
 *
 * IMPORTANT: This saves directly to the C++ registry so that C++ service providers
 * (like LlamaCPP) can find the model when loading. The framework field is critical
 * for correct backend selection.
 */
internal actual fun registerModelInternal(modelInfo: ModelInfo) {
    try {
        // Convert public ModelInfo to bridge ModelInfo
        // CRITICAL: The framework field must be set correctly for C++ can_handle() to work
        val bridgeModelInfo =
            CppBridgeModelRegistry.ModelInfo(
                modelId = modelInfo.id,
                name = modelInfo.name,
                category =
                    when (modelInfo.category) {
                        ModelCategory.LANGUAGE -> CppBridgeModelRegistry.ModelCategory.LANGUAGE
                        ModelCategory.SPEECH_RECOGNITION -> CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION
                        ModelCategory.SPEECH_SYNTHESIS -> CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS
                        ModelCategory.AUDIO -> CppBridgeModelRegistry.ModelCategory.AUDIO
                        else -> CppBridgeModelRegistry.ModelCategory.LANGUAGE
                    },
                format =
                    when (modelInfo.format) {
                        ModelFormat.GGUF -> CppBridgeModelRegistry.ModelFormat.GGUF
                        ModelFormat.ONNX -> CppBridgeModelRegistry.ModelFormat.ONNX
                        ModelFormat.ORT -> CppBridgeModelRegistry.ModelFormat.ORT
                        else -> CppBridgeModelRegistry.ModelFormat.UNKNOWN
                    },
                // CRITICAL: Map InferenceFramework to C++ framework constant
                framework =
                    when (modelInfo.framework) {
                        InferenceFramework.LLAMA_CPP -> CppBridgeModelRegistry.Framework.LLAMACPP
                        InferenceFramework.ONNX -> CppBridgeModelRegistry.Framework.ONNX
                        InferenceFramework.FOUNDATION_MODELS -> CppBridgeModelRegistry.Framework.FOUNDATION_MODELS
                        InferenceFramework.SYSTEM_TTS -> CppBridgeModelRegistry.Framework.SYSTEM_TTS
                        InferenceFramework.FLUID_AUDIO -> CppBridgeModelRegistry.Framework.FLUID_AUDIO
                        InferenceFramework.BUILT_IN -> CppBridgeModelRegistry.Framework.BUILTIN
                        InferenceFramework.NONE -> CppBridgeModelRegistry.Framework.NONE
                        InferenceFramework.UNKNOWN -> CppBridgeModelRegistry.Framework.UNKNOWN
                    },
                downloadUrl = modelInfo.downloadURL,
                localPath = modelInfo.localPath,
                downloadSize = modelInfo.downloadSize ?: 0,
                contextLength = modelInfo.contextLength ?: 0,
                supportsThinking = modelInfo.supportsThinking,
                description = modelInfo.description,
                status = CppBridgeModelRegistry.ModelStatus.AVAILABLE,
            )

        // Save directly to C++ registry - this is where C++ backends look for models
        CppBridgeModelRegistry.save(bridgeModelInfo)

        // Also add to the in-memory cache for immediate availability from Kotlin
        addToModelCache(modelInfo)

        registrationLogger.info("Registered model: ${modelInfo.name} (${modelInfo.id})")
    } catch (e: Exception) {
        registrationLogger.error("Failed to register model: ${e.message}")
    }
}

// In-memory model cache for registered models
private val registeredModels = mutableListOf<ModelInfo>()
private val modelCacheLock = Any()

private fun addToModelCache(modelInfo: ModelInfo) {
    synchronized(modelCacheLock) {
        // Remove existing if present (update)
        registeredModels.removeAll { it.id == modelInfo.id }
        registeredModels.add(modelInfo)
    }
}

private fun getRegisteredModels(): List<ModelInfo> {
    synchronized(modelCacheLock) {
        return registeredModels.toList()
    }
}

// Convert CppBridgeModelRegistry.ModelInfo to public ModelInfo
private fun CppBridgeModelRegistry.ModelInfo.toPublicModelInfo(): ModelInfo {
    return bridgeModelToPublic(this)
}

private fun getAllBridgeModels(): List<CppBridgeModelRegistry.ModelInfo> {
    // Get all models directly from C++ registry
    return CppBridgeModelRegistry.getAll()
}

// Track if we've scanned for downloaded models
@Volatile
private var hasScannedForDownloads = false
private val scanLock = Any()

actual suspend fun RunAnywhere.availableModels(): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Scan for downloaded models once on first call
    synchronized(scanLock) {
        if (!hasScannedForDownloads) {
            CppBridgeModelRegistry.scanAndRestoreDownloadedModels()
            syncRegisteredModelsWithBridge()
            hasScannedForDownloads = true
        }
    }

    // Get models from in-memory cache (registered via registerModel())
    val registeredModelList = getRegisteredModels()

    // Get models from C++ bridge
    val bridgeModels = getAllBridgeModels().map { it.toPublicModelInfo() }

    // Merge both lists, with registered models taking precedence
    val allModels = mutableMapOf<String, ModelInfo>()
    for (model in bridgeModels) {
        allModels[model.id] = model
    }
    for (model in registeredModelList) {
        allModels[model.id] = model
    }

    return allModels.values.toList()
}

/**
 * Sync the registered models cache with the bridge registry.
 * This updates localPath for models that were found on disk.
 */
private fun syncRegisteredModelsWithBridge() {
    synchronized(modelCacheLock) {
        val updatedModels = mutableListOf<ModelInfo>()
        for (model in registeredModels) {
            // Check bridge registry for updated info (especially localPath)
            val bridgeModel = CppBridgeModelRegistry.get(model.id)
            if (bridgeModel != null && bridgeModel.localPath != null) {
                // Model was found on disk, update local path (isDownloaded is computed from localPath)
                updatedModels.add(model.copy(localPath = bridgeModel.localPath))
            } else {
                updatedModels.add(model)
            }
        }
        registeredModels.clear()
        registeredModels.addAll(updatedModels)
    }
}

actual suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val type =
        when (category) {
            ModelCategory.LANGUAGE -> CppBridgeModelRegistry.ModelType.LLM
            ModelCategory.SPEECH_RECOGNITION -> CppBridgeModelRegistry.ModelType.STT
            ModelCategory.SPEECH_SYNTHESIS -> CppBridgeModelRegistry.ModelType.TTS
            ModelCategory.AUDIO -> CppBridgeModelRegistry.ModelType.VAD
            else -> return emptyList()
        }
    return CppBridgeModelRegistry.getModelsByType(type).map { bridgeModelToPublic(it) }
}

actual suspend fun RunAnywhere.downloadedModels(): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    return CppBridgeModelRegistry.getDownloaded().map { bridgeModelToPublic(it) }
}

actual suspend fun RunAnywhere.model(modelId: String): ModelInfo? {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Get model from C++ registry
    val bridgeModel = CppBridgeModelRegistry.get(modelId) ?: return null
    return bridgeModelToPublic(bridgeModel)
}

// Convert CppBridgeModelRegistry.ModelInfo to public ModelInfo
private fun bridgeModelToPublic(bridge: CppBridgeModelRegistry.ModelInfo): ModelInfo {
    return ModelInfo(
        id = bridge.modelId,
        name = bridge.name,
        category =
            when (bridge.category) {
                CppBridgeModelRegistry.ModelCategory.LANGUAGE -> ModelCategory.LANGUAGE
                CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION -> ModelCategory.SPEECH_RECOGNITION
                CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS -> ModelCategory.SPEECH_SYNTHESIS
                CppBridgeModelRegistry.ModelCategory.AUDIO -> ModelCategory.AUDIO
                else -> ModelCategory.LANGUAGE
            },
        format =
            when (bridge.format) {
                CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
                CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
                CppBridgeModelRegistry.ModelFormat.ORT -> ModelFormat.ORT
                else -> ModelFormat.UNKNOWN
            },
        framework =
            when (bridge.framework) {
                CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.LLAMA_CPP
                CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.ONNX
                CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.FOUNDATION_MODELS
                CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.SYSTEM_TTS
                else -> InferenceFramework.UNKNOWN
            },
        downloadURL = bridge.downloadUrl,
        localPath = bridge.localPath,
        downloadSize = if (bridge.downloadSize > 0) bridge.downloadSize else null,
        contextLength = if (bridge.contextLength > 0) bridge.contextLength else null,
        supportsThinking = bridge.supportsThinking,
        description = bridge.description,
    )
}

/**
 * Download a model by ID.
 *
 * Mirrors Swift `RunAnywhere.downloadModel()` exactly:
 * 1. Gets model info from registry
 * 2. Starts download via CppBridgeDownload
 * 3. Handles archive extraction for .tar.gz and .zip
 * 4. Updates model registry with local path
 *
 * @param modelId The model ID to download
 * @return Flow of DownloadProgress updates
 */
actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> =
    callbackFlow {
        val downloadLogger = SDKLogger("RunAnywhere.Download")

        // 0. Check network connectivity first (for better user experience)
        val (isNetworkAvailable, networkDescription) = CppBridgeDownload.checkNetworkStatus()
        if (!isNetworkAvailable) {
            downloadLogger.error("No internet connection: $networkDescription")
            throw SDKError.networkUnavailable(
                IllegalStateException("No internet connection. Please check your network settings and try again."),
            )
        }
        downloadLogger.debug("Network status: $networkDescription")

        // 1. Get model info from registered models
        val modelInfo =
            getRegisteredModels().find { it.id == modelId }
                ?: throw SDKError.model("Model '$modelId' not found in registry")

        val downloadUrl =
            modelInfo.downloadURL
                ?: throw SDKError.model("Model '$modelId' has no download URL")

        downloadLogger.info("Starting download for model: $modelId")
        downloadLogger.info("  URL: $downloadUrl")
        downloadLogger.info("  Category: ${modelInfo.category}")
        downloadLogger.info("  Framework: ${modelInfo.framework}")

        // 2. Emit initial progress
        trySend(
            DownloadProgress(
                modelId = modelId,
                progress = 0f,
                bytesDownloaded = 0,
                totalBytes = modelInfo.downloadSize,
                state = DownloadState.PENDING,
            ),
        )

        // 3. Determine model type for path resolution
        val modelType =
            when (modelInfo.category) {
                ModelCategory.LANGUAGE -> CppBridgeModelRegistry.ModelType.LLM
                ModelCategory.SPEECH_RECOGNITION -> CppBridgeModelRegistry.ModelType.STT
                ModelCategory.SPEECH_SYNTHESIS -> CppBridgeModelRegistry.ModelType.TTS
                ModelCategory.AUDIO -> CppBridgeModelRegistry.ModelType.VAD
                else -> CppBridgeModelRegistry.ModelType.LLM
            }

        // 4. Emit download started event and record start time
        val downloadStartTime = System.currentTimeMillis()
        CppBridgeEvents.emitDownloadStarted(modelId, modelInfo.downloadSize ?: 0)

        // 5. Create a CompletableDeferred to wait for download completion
        // This is used to properly suspend until the async download finishes
        data class DownloadResult(
            val success: Boolean,
            val filePath: String?,
            val fileSize: Long,
            val error: String?,
        )
        val downloadCompletion = CompletableDeferred<DownloadResult>()

        // 6. Set up download listener to convert callbacks to Flow
        val downloadListener =
            object : CppBridgeDownload.DownloadListener {
                override fun onDownloadStarted(downloadId: String, modelId: String, url: String) {
                    downloadLogger.debug("Download actually started: $downloadId")
                    trySend(
                        DownloadProgress(
                            modelId = modelId,
                            progress = 0f,
                            bytesDownloaded = 0,
                            totalBytes = modelInfo.downloadSize,
                            state = DownloadState.DOWNLOADING,
                        ),
                    )
                }

                override fun onDownloadProgress(downloadId: String, downloadedBytes: Long, totalBytes: Long, progress: Int) {
                    val progressFraction = progress.toFloat() / 100f
                    downloadLogger.debug("Download progress: $progress% ($downloadedBytes / $totalBytes)")

                    // Emit progress event every 5%
                    if (progress % 5 == 0) {
                        CppBridgeEvents.emitDownloadProgress(modelId, progressFraction.toDouble(), downloadedBytes, totalBytes)
                    }

                    trySend(
                        DownloadProgress(
                            modelId = modelId,
                            progress = progressFraction,
                            bytesDownloaded = downloadedBytes,
                            totalBytes = if (totalBytes > 0) totalBytes else modelInfo.downloadSize,
                            state = DownloadState.DOWNLOADING,
                        ),
                    )
                }

                override fun onDownloadCompleted(downloadId: String, modelId: String, filePath: String, fileSize: Long) {
                    downloadLogger.info("Download completed callback: $filePath ($fileSize bytes)")
                    // Signal completion to the waiting coroutine
                    downloadCompletion.complete(
                        DownloadResult(
                            success = true,
                            filePath = filePath,
                            fileSize = fileSize,
                            error = null,
                        ),
                    )
                }

                override fun onDownloadFailed(downloadId: String, modelId: String, error: Int, errorMessage: String) {
                    downloadLogger.error("Download failed callback: $errorMessage (error code: $error)")
                    // Signal failure to the waiting coroutine
                    downloadCompletion.complete(
                        DownloadResult(
                            success = false,
                            filePath = null,
                            fileSize = 0,
                            error = errorMessage,
                        ),
                    )
                }

                override fun onDownloadPaused(downloadId: String) {
                    downloadLogger.info("Download paused: $downloadId")
                    trySend(
                        DownloadProgress(
                            modelId = modelId,
                            progress = 0f,
                            bytesDownloaded = 0,
                            totalBytes = modelInfo.downloadSize,
                            state = DownloadState.PENDING,
                        ),
                    )
                }

                override fun onDownloadResumed(downloadId: String) {
                    downloadLogger.info("Download resumed: $downloadId")
                }

                override fun onDownloadCancelled(downloadId: String) {
                    downloadLogger.info("Download cancelled: $downloadId")
                    downloadCompletion.complete(
                        DownloadResult(
                            success = false,
                            filePath = null,
                            fileSize = 0,
                            error = "Download cancelled",
                        ),
                    )
                }
            }

        // Register listener BEFORE starting download
        CppBridgeDownload.downloadListener = downloadListener

        try {
            // 7. Start the actual download (runs asynchronously on thread pool)
            val downloadId =
                CppBridgeDownload.startDownload(
                    url = downloadUrl,
                    modelId = modelId,
                    modelType = modelType,
                    priority = CppBridgeDownload.DownloadPriority.NORMAL,
                    expectedChecksum = null,
                ) ?: throw SDKError.download("Failed to start download for model: $modelId")

            downloadLogger.info("Download queued with ID: $downloadId, waiting for completion...")

            // 8. Wait for download to complete (suspends until callback fires)
            val result = downloadCompletion.await()

            // 9. Handle result
            if (!result.success) {
                val errorMsg = result.error ?: "Unknown download error"
                CppBridgeEvents.emitDownloadFailed(modelId, errorMsg)
                trySend(
                    DownloadProgress(
                        modelId = modelId,
                        progress = 0f,
                        bytesDownloaded = 0,
                        totalBytes = modelInfo.downloadSize,
                        state = DownloadState.ERROR,
                        error = errorMsg,
                    ),
                )
                throw SDKError.download("Download failed for model: $modelId - $errorMsg")
            }

            // 10. Get the downloaded file path
            val downloadedPath = result.filePath ?: CppBridgeModelPaths.getModelPath(modelId, modelType)
            val downloadedFile = File(downloadedPath)

            downloadLogger.info("Downloaded file: $downloadedPath (exists: ${downloadedFile.exists()}, size: ${result.fileSize})")

            // 11. Handle extraction if needed (for .tar.gz, .tar.bz2, or .zip archives)
            val finalModelPath =
                if (requiresExtraction(downloadUrl)) {
                    downloadLogger.info("Archive detected in URL, extracting...")
                    trySend(
                        DownloadProgress(
                            modelId = modelId,
                            progress = 0.95f,
                            bytesDownloaded = result.fileSize,
                            totalBytes = result.fileSize,
                            state = DownloadState.EXTRACTING,
                        ),
                    )

                    // Pass the URL to determine archive type (file may be saved without extension)
                    val extractedPath = extractArchive(downloadedFile, modelId, modelType, downloadUrl, downloadLogger)
                    downloadLogger.info("Extraction complete: $extractedPath")
                    extractedPath
                } else {
                    downloadedPath
                }

            // 12. Update model in C++ registry with local path
            val updatedModelInfo = modelInfo.copy(localPath = finalModelPath)
            addToModelCache(updatedModelInfo)
            CppBridgeModelRegistry.updateDownloadStatus(modelId, finalModelPath)

            downloadLogger.info("Model ready at: $finalModelPath")

            // 13. Emit completion events
            val downloadDurationMs = System.currentTimeMillis() - downloadStartTime
            CppBridgeEvents.emitDownloadCompleted(modelId, downloadDurationMs.toDouble(), result.fileSize)

            trySend(
                DownloadProgress(
                    modelId = modelId,
                    progress = 1f,
                    bytesDownloaded = result.fileSize,
                    totalBytes = result.fileSize,
                    state = DownloadState.COMPLETED,
                ),
            )

            // Close the channel to signal completion to collectors
            close()
        } catch (e: Exception) {
            downloadLogger.error("Download error: ${e.message}")
            CppBridgeEvents.emitDownloadFailed(modelId, e.message ?: "Unknown error")
            // Close with exception so collectors receive the error
            close(e)
        } finally {
            // Clean up listener
            CppBridgeDownload.downloadListener = null
        }

        awaitClose {
            downloadLogger.debug("Download flow closed for: $modelId")
        }
    }

/**
 * Check if URL requires extraction (is an archive).
 * Supports: .tar.gz, .tgz, .tar.bz2, .tbz2, .zip
 */
private fun requiresExtraction(url: String): Boolean {
    val lowercaseUrl = url.lowercase()
    return lowercaseUrl.endsWith(".tar.gz") ||
        lowercaseUrl.endsWith(".tgz") ||
        lowercaseUrl.endsWith(".tar.bz2") ||
        lowercaseUrl.endsWith(".tbz2") ||
        lowercaseUrl.endsWith(".zip")
}

/**
 * Extract an archive to the model directory.
 *
 * Supports:
 * - .tar.gz / .tgz → Uses Apache Commons Compress
 * - .tar.bz2 / .tbz2 → Uses Apache Commons Compress
 * - .zip → Uses java.util.zip
 *
 * Archives typically contain a root folder (e.g., sherpa-onnx-whisper-tiny.en/)
 * so we extract to the parent directory and the archive structure creates the model folder.
 *
 * @param archiveFile The downloaded archive file (may not have extension in filename)
 * @param modelId The model ID
 * @param modelType The model type
 * @param originalUrl The original download URL (used to determine archive type)
 * @param logger Logger for debug output
 */
@Suppress("UNUSED_PARAMETER")
private suspend fun extractArchive(
    archiveFile: File,
    modelId: String,
    modelType: Int, // Reserved for future type-specific extraction logic
    originalUrl: String,
    logger: SDKLogger,
): String =
    withContext(Dispatchers.IO) {
        // Extract to parent directory - the archive typically contains a root folder
        // e.g., archive contains: sherpa-onnx-whisper-tiny.en/tiny.en-decoder.onnx
        // So we extract to /models/stt/ and get /models/stt/sherpa-onnx-whisper-tiny.en/
        val parentDir = archiveFile.parentFile
        if (parentDir == null || !parentDir.exists()) {
            throw SDKError.download("Cannot determine extraction directory for: ${archiveFile.absolutePath}")
        }

        logger.info("Extracting to parent: ${parentDir.absolutePath}")
        logger.debug("Archive file: ${archiveFile.absolutePath}")
        logger.debug("Original URL: $originalUrl")

        // Use the URL to determine archive type (file may be saved without extension)
        val lowercaseUrl = originalUrl.lowercase()

        // IMPORTANT: The archive file name might conflict with the folder inside the archive
        // (e.g., file "sherpa-onnx-whisper-tiny.en" and archive contains folder "sherpa-onnx-whisper-tiny.en/")
        // We need to rename/move the archive before extracting to avoid ENOTDIR errors
        val tempArchiveFile = File(parentDir, "${archiveFile.name}.tmp_archive")
        try {
            if (!archiveFile.renameTo(tempArchiveFile)) {
                // If rename fails, copy and delete
                archiveFile.copyTo(tempArchiveFile, overwrite = true)
                archiveFile.delete()
            }
            logger.debug("Moved archive to temp: ${tempArchiveFile.absolutePath}")
        } catch (e: Exception) {
            logger.error("Failed to move archive to temp location: ${e.message}")
            throw SDKError.download("Failed to prepare archive for extraction: ${e.message}")
        }

        try {
            when {
                lowercaseUrl.endsWith(".tar.gz") || lowercaseUrl.endsWith(".tgz") -> {
                    logger.info("Extracting tar.gz archive...")
                    extractTarGz(tempArchiveFile, parentDir, logger)
                }
                lowercaseUrl.endsWith(".tar.bz2") || lowercaseUrl.endsWith(".tbz2") -> {
                    logger.info("Extracting tar.bz2 archive...")
                    extractTarBz2(tempArchiveFile, parentDir, logger)
                }
                lowercaseUrl.endsWith(".zip") -> {
                    logger.info("Extracting zip archive...")
                    extractZip(tempArchiveFile, parentDir, logger)
                }
                else -> {
                    logger.warn("Unknown archive type for URL: $originalUrl")
                    // Restore the original file
                    tempArchiveFile.renameTo(archiveFile)
                    return@withContext archiveFile.absolutePath
                }
            }
        } finally {
            // Always clean up the temp archive file
            try {
                if (tempArchiveFile.exists()) {
                    tempArchiveFile.delete()
                    logger.debug("Cleaned up temp archive: ${tempArchiveFile.absolutePath}")
                }
            } catch (e: Exception) {
                logger.warn("Failed to clean up temp archive: ${e.message}")
            }
        }

        // Find the extracted model directory
        // The archive should have created a folder with the model ID name
        val expectedModelDir = File(parentDir, modelId)
        val finalPath =
            if (expectedModelDir.exists() && expectedModelDir.isDirectory) {
                expectedModelDir.absolutePath
            } else {
                // Fallback: look for any new directory created
                parentDir
                    .listFiles()
                    ?.firstOrNull {
                        it.isDirectory && it.name.contains(modelId.substringBefore("-"))
                    }?.absolutePath ?: parentDir.absolutePath
            }

        logger.info("Model extracted to: $finalPath")
        finalPath
    }

/**
 * Extract a .tar.gz archive.
 */
private fun extractTarGz(archiveFile: File, destDir: File, logger: SDKLogger) {
    logger.debug("Extracting tar.gz: ${archiveFile.absolutePath}")

    FileInputStream(archiveFile).use { fis ->
        BufferedInputStream(fis).use { bis ->
            GzipCompressorInputStream(bis).use { gzis ->
                TarArchiveInputStream(gzis).use { tais ->
                    var entry = tais.nextEntry
                    var fileCount = 0

                    while (entry != null) {
                        val destFile = File(destDir, entry.name)

                        // Security check - prevent path traversal
                        if (!destFile.canonicalPath.startsWith(destDir.canonicalPath)) {
                            throw SecurityException("Tar entry outside destination: ${entry.name}")
                        }

                        if (entry.isDirectory) {
                            destFile.mkdirs()
                        } else {
                            destFile.parentFile?.mkdirs()
                            FileOutputStream(destFile).use { fos ->
                                tais.copyTo(fos)
                            }
                            fileCount++
                        }

                        entry = tais.nextEntry
                    }

                    logger.info("Extracted $fileCount files from tar.gz")
                }
            }
        }
    }
}

/**
 * Extract a .tar.bz2 archive.
 */
private fun extractTarBz2(archiveFile: File, destDir: File, logger: SDKLogger) {
    logger.debug("Extracting tar.bz2: ${archiveFile.absolutePath}")

    FileInputStream(archiveFile).use { fis ->
        BufferedInputStream(fis).use { bis ->
            BZip2CompressorInputStream(bis).use { bzis ->
                TarArchiveInputStream(bzis).use { tais ->
                    var entry = tais.nextEntry
                    var fileCount = 0

                    while (entry != null) {
                        val destFile = File(destDir, entry.name)

                        // Security check - prevent path traversal
                        if (!destFile.canonicalPath.startsWith(destDir.canonicalPath)) {
                            throw SecurityException("Tar entry outside destination: ${entry.name}")
                        }

                        if (entry.isDirectory) {
                            destFile.mkdirs()
                        } else {
                            destFile.parentFile?.mkdirs()
                            FileOutputStream(destFile).use { fos ->
                                tais.copyTo(fos)
                            }
                            fileCount++
                        }

                        entry = tais.nextEntry
                    }

                    logger.info("Extracted $fileCount files from tar.bz2")
                }
            }
        }
    }
}

/**
 * Extract a .zip archive.
 */
private fun extractZip(archiveFile: File, destDir: File, logger: SDKLogger) {
    logger.debug("Extracting zip: ${archiveFile.absolutePath}")

    ZipInputStream(FileInputStream(archiveFile)).use { zis ->
        var entry = zis.nextEntry
        var fileCount = 0

        while (entry != null) {
            val destFile = File(destDir, entry.name)

            // Security check - prevent path traversal
            if (!destFile.canonicalPath.startsWith(destDir.canonicalPath)) {
                throw SecurityException("Zip entry outside destination: ${entry.name}")
            }

            if (entry.isDirectory) {
                destFile.mkdirs()
            } else {
                destFile.parentFile?.mkdirs()
                FileOutputStream(destFile).use { fos ->
                    zis.copyTo(fos)
                }
                fileCount++
            }

            zis.closeEntry()
            entry = zis.nextEntry
        }

        logger.info("Extracted $fileCount files from zip")
    }
}

actual suspend fun RunAnywhere.cancelDownload(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Update C++ registry to mark download cancelled
    CppBridgeModelRegistry.updateDownloadStatus(modelId, null)
}

actual suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val model = CppBridgeModelRegistry.get(modelId) ?: return false
    return model.localPath != null && model.localPath.isNotEmpty()
}

actual suspend fun RunAnywhere.deleteModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeModelRegistry.remove(modelId)
}

actual suspend fun RunAnywhere.deleteAllModels() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Would need to parse and delete each - simplified
}

actual suspend fun RunAnywhere.refreshModelRegistry() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Trigger registry refresh via native call
    // TODO: Implement via CppBridge
}

actual suspend fun RunAnywhere.loadLLMModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val model =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKError.model("Model '$modelId' not found in registry")

    val localPath =
        model.localPath
            ?: throw SDKError.model("Model '$modelId' is not downloaded")

    // Pass modelPath, modelId, and modelName separately for correct telemetry
    val result = CppBridgeLLM.loadModel(localPath, modelId, model.name)
    if (result != 0) {
        throw SDKError.llm("Failed to load LLM model '$modelId' (error code: $result)")
    }
}

actual suspend fun RunAnywhere.unloadLLMModel() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeLLM.unload()
}

actual suspend fun RunAnywhere.isLLMModelLoaded(): Boolean {
    return CppBridgeLLM.isLoaded
}

actual val RunAnywhere.currentLLMModelId: String?
    get() = CppBridgeLLM.getLoadedModelId()

actual suspend fun RunAnywhere.currentLLMModel(): ModelInfo? {
    val modelId = CppBridgeLLM.getLoadedModelId() ?: return null
    // Look up in registered models first
    val registeredModel = getRegisteredModels().find { it.id == modelId }
    if (registeredModel != null) return registeredModel
    // Fall back to bridge models
    return getAllBridgeModels().find { it.modelId == modelId }?.toPublicModelInfo()
}

actual suspend fun RunAnywhere.currentSTTModel(): ModelInfo? {
    val modelId = CppBridgeSTT.getLoadedModelId() ?: return null
    // Look up in registered models first
    val registeredModel = getRegisteredModels().find { it.id == modelId }
    if (registeredModel != null) return registeredModel
    // Fall back to bridge models
    return getAllBridgeModels().find { it.modelId == modelId }?.toPublicModelInfo()
}

actual suspend fun RunAnywhere.loadSTTModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val model =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKError.model("Model '$modelId' not found in registry")

    val localPath =
        model.localPath
            ?: throw SDKError.model("Model '$modelId' is not downloaded")

    // Pass modelPath, modelId, and modelName separately for correct telemetry
    val result = CppBridgeSTT.loadModel(localPath, modelId, model.name)
    if (result != 0) {
        throw SDKError.stt("Failed to load STT model '$modelId' (error code: $result)")
    }
}
