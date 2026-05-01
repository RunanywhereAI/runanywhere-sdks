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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadState
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

// MARK: - Multi-File Model Companion Storage

/** Stores companion file (url → filename) pairs for multi-file models, keyed by modelId. */
private val modelCompanionFiles = mutableMapOf<String, List<Pair<String, String>>>()
private val companionFilesLock = Any()
private val activeDownloadIdsByModel = ConcurrentHashMap<String, String>()

internal actual fun registerCompanionFilesInternal(modelId: String, companionFiles: List<Pair<String, String>>) {
    synchronized(companionFilesLock) {
        modelCompanionFiles[modelId] = companionFiles
    }
}

private fun getCompanionFiles(modelId: String): List<Pair<String, String>>? =
    synchronized(companionFilesLock) { modelCompanionFiles[modelId]?.toList() }

// MARK: - Model Registration Implementation

private val modelsLogger = SDKLogger.models

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
                        ModelCategory.VISION -> CppBridgeModelRegistry.ModelCategory.VISION
                        ModelCategory.EMBEDDING -> CppBridgeModelRegistry.ModelCategory.EMBEDDING
                        ModelCategory.IMAGE_GENERATION -> CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION
                        ModelCategory.MULTIMODAL -> CppBridgeModelRegistry.ModelCategory.MULTIMODAL
                    },
                format =
                    when (modelInfo.format) {
                        ModelFormat.GGUF -> CppBridgeModelRegistry.ModelFormat.GGUF
                        ModelFormat.ONNX -> CppBridgeModelRegistry.ModelFormat.ONNX
                        ModelFormat.ORT -> CppBridgeModelRegistry.ModelFormat.ORT
                        ModelFormat.BIN -> CppBridgeModelRegistry.ModelFormat.BIN
                        ModelFormat.QNN_CONTEXT -> CppBridgeModelRegistry.ModelFormat.QNN_CONTEXT
                        else -> CppBridgeModelRegistry.ModelFormat.UNKNOWN
                    },
                // CRITICAL: Map InferenceFramework to C++ framework constant
                framework =
                    when (modelInfo.framework) {
                        InferenceFramework.LLAMA_CPP -> CppBridgeModelRegistry.Framework.LLAMACPP
                        InferenceFramework.ONNX -> CppBridgeModelRegistry.Framework.ONNX
                        InferenceFramework.SHERPA -> CppBridgeModelRegistry.Framework.SHERPA
                        InferenceFramework.FOUNDATION_MODELS -> CppBridgeModelRegistry.Framework.FOUNDATION_MODELS
                        InferenceFramework.SYSTEM_TTS -> CppBridgeModelRegistry.Framework.SYSTEM_TTS
                        InferenceFramework.FLUID_AUDIO -> CppBridgeModelRegistry.Framework.FLUID_AUDIO
                        InferenceFramework.BUILT_IN -> CppBridgeModelRegistry.Framework.BUILTIN
                        InferenceFramework.NONE -> CppBridgeModelRegistry.Framework.NONE
                        InferenceFramework.GENIE -> CppBridgeModelRegistry.Framework.GENIE
                        InferenceFramework.UNKNOWN -> CppBridgeModelRegistry.Framework.UNKNOWN
                    },
                downloadUrl = modelInfo.downloadURL,
                localPath = modelInfo.localPath,
                downloadSize = modelInfo.downloadSize ?: 0,
                contextLength = modelInfo.contextLength ?: 0,
                supportsThinking = modelInfo.supportsThinking,
                supportsLora = modelInfo.supportsLora,
                description = modelInfo.description,
                status = CppBridgeModelRegistry.ModelStatus.AVAILABLE,
            )

        // Save directly to C++ registry - this is where C++ backends look for models
        CppBridgeModelRegistry.save(bridgeModelInfo)

        // Also add to the in-memory cache for immediate availability from Kotlin
        addToModelCache(modelInfo)

        modelsLogger.info("Registered model: ${modelInfo.name} (${modelInfo.id})")
    } catch (e: Exception) {
        modelsLogger.error("Failed to register model: ${e.message}")
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

// MARK: - Multi-File Model Cache

/** Cache for multi-file model descriptors (C++ registry doesn't preserve file arrays) */
private val multiFileModelCache = mutableMapOf<String, List<ModelFileDescriptor>>()
private val multiFileCacheLock = Any()

/**
 * Cache multi-file descriptors for later retrieval during download.
 */
internal actual fun cacheMultiFileDescriptors(modelId: String, files: List<ModelFileDescriptor>) {
    synchronized(multiFileCacheLock) {
        multiFileModelCache[modelId] = files
    }
}

/**
 * Get cached file descriptors for a multi-file model.
 */
actual fun getMultiFileDescriptors(modelId: String): List<ModelFileDescriptor>? {
    synchronized(multiFileCacheLock) {
        return multiFileModelCache[modelId]
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
        throw SDKException.notInitialized("SDK not initialized")
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
        throw SDKException.notInitialized("SDK not initialized")
    }
    val type =
        when (category) {
            ModelCategory.LANGUAGE -> CppBridgeModelRegistry.ModelCategory.LANGUAGE
            ModelCategory.SPEECH_RECOGNITION -> CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION
            ModelCategory.SPEECH_SYNTHESIS -> CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS
            ModelCategory.AUDIO -> CppBridgeModelRegistry.ModelCategory.AUDIO
            ModelCategory.VISION -> CppBridgeModelRegistry.ModelCategory.VISION
            ModelCategory.IMAGE_GENERATION -> CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION
            ModelCategory.MULTIMODAL -> CppBridgeModelRegistry.ModelCategory.MULTIMODAL
            ModelCategory.EMBEDDING -> CppBridgeModelRegistry.ModelCategory.EMBEDDING
        }
    return CppBridgeModelRegistry.getModelsByType(type).map { bridgeModelToPublic(it) }
}

actual suspend fun RunAnywhere.downloadedModels(): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeModelRegistry.getDownloaded().map { bridgeModelToPublic(it) }
}

actual suspend fun RunAnywhere.model(modelId: String): ModelInfo? {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
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
                CppBridgeModelRegistry.ModelCategory.VISION -> ModelCategory.VISION
                CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION -> ModelCategory.IMAGE_GENERATION
                CppBridgeModelRegistry.ModelCategory.MULTIMODAL -> ModelCategory.MULTIMODAL
                else -> ModelCategory.LANGUAGE
            },
        format =
            when (bridge.format) {
                CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
                CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
                CppBridgeModelRegistry.ModelFormat.ORT -> ModelFormat.ORT
                CppBridgeModelRegistry.ModelFormat.BIN -> ModelFormat.BIN
                CppBridgeModelRegistry.ModelFormat.QNN_CONTEXT -> ModelFormat.QNN_CONTEXT
                else -> ModelFormat.UNKNOWN
            },
        framework =
            when (bridge.framework) {
                CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.LLAMA_CPP
                CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.ONNX
                CppBridgeModelRegistry.Framework.SHERPA -> InferenceFramework.SHERPA
                CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.FOUNDATION_MODELS
                CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.SYSTEM_TTS
                CppBridgeModelRegistry.Framework.GENIE -> InferenceFramework.GENIE
                else -> InferenceFramework.UNKNOWN
            },
        downloadURL = bridge.downloadUrl,
        localPath = bridge.localPath,
        downloadSize = if (bridge.downloadSize > 0) bridge.downloadSize else null,
        contextLength = if (bridge.contextLength > 0) bridge.contextLength else null,
        supportsThinking = bridge.supportsThinking,
        supportsLora = bridge.supportsLora,
        description = bridge.description,
    )
}

/**
 * Download a model by ID.
 *
 * Consolidated in M3: routes ALL model kinds (single-file, multi-file/VLM,
 * embedding with companions) through one `performDownload` helper that uses
 * the C++ download primitives (`racHttpDownloadExecute` for bytes,
 * `nativeExtractArchive` + `nativeFindModelPathAfterExtraction` for archives).
 *
 * Previously this function had three parallel code paths (~500 LOC) with
 * duplicate state machines, retry loops, progress aggregation, and phase
 * transitions. All of that now lives in `runanywhere-commons` behind the
 * `rac_http_download_execute` C ABI; Kotlin only wires the Flow/coroutine
 * surface on top.
 *
 * @param modelId The model ID to download
 * @return Flow of DownloadProgress updates
 */
actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> =
    callbackFlow {
        val downloadLogger = SDKLogger.download

        // Preflight network check (better UX than mid-stream failure)
        val (isNetworkAvailable, networkDescription) = CppBridgeDownload.checkNetworkStatus()
        if (!isNetworkAvailable) {
            downloadLogger.error("No internet connection: $networkDescription")
            throw SDKException.networkUnavailable(
                IllegalStateException("No internet connection. Please check your network settings and try again."),
            )
        }
        downloadLogger.debug("Network status: $networkDescription")

        // Resolve model info: registered-first, then remote catalog fallback.
        val modelInfo =
            getRegisteredModels().find { it.id == modelId }
                ?: getAllBridgeModels().find { it.modelId == modelId }?.toPublicModelInfo()
                ?: throw SDKException.model("Model '$modelId' not found in registry")

        val downloadUrl =
            modelInfo.downloadURL
                ?: throw SDKException.model("Model '$modelId' has no download URL")

        downloadLogger.info("Starting download for model: $modelId (category=${modelInfo.category}, framework=${modelInfo.framework})")
        downloadLogger.info("  URL: $downloadUrl")

        val downloadStartTime = System.currentTimeMillis()
        CppBridgeEvents.emitDownloadStarted(modelId, modelInfo.downloadSize ?: 0)

        trySend(
            DownloadProgress(
                model_id = modelId,
                stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
                bytes_downloaded = 0,
                total_bytes = modelInfo.downloadSize ?: 0,
                stage_progress = 0f,
                state = DownloadState.DOWNLOAD_STATE_PENDING,
            ),
        )

        try {
            val finalPath =
                withContext(Dispatchers.IO) {
                    performDownload(
                        modelId = modelId,
                        modelInfo = modelInfo,
                        primaryUrl = downloadUrl,
                        emit = { p -> trySend(p) },
                        logger = downloadLogger,
                    )
                }

            // Persist the resolved on-disk location in the registry so later
            // cold-start scans see this model as downloaded.
            val updatedModelInfo = modelInfo.copy(localPath = finalPath)
            addToModelCache(updatedModelInfo)
            CppBridgeModelRegistry.updateDownloadStatus(modelId, finalPath)
            CppBridgeStorage.storeString(CppBridgeStorage.StorageNamespace.DOWNLOADS, modelId, finalPath)

            val downloadDurationMs = System.currentTimeMillis() - downloadStartTime
            CppBridgeEvents.emitDownloadCompleted(modelId, downloadDurationMs.toDouble(), 0)
            downloadLogger.info("Model ready at: $finalPath")

            trySend(
                DownloadProgress(
                    model_id = modelId,
                    stage = DownloadStage.DOWNLOAD_STAGE_COMPLETED,
                    bytes_downloaded = 0,
                    total_bytes = modelInfo.downloadSize ?: 0,
                    stage_progress = 1f,
                    state = DownloadState.DOWNLOAD_STATE_COMPLETED,
                ),
            )
            close()
        } catch (e: Exception) {
            downloadLogger.error("Download error: ${e.message}")
            CppBridgeEvents.emitDownloadFailed(modelId, e.message ?: "Unknown error")
            trySend(
                DownloadProgress(
                    model_id = modelId,
                    stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
                    bytes_downloaded = 0,
                    total_bytes = modelInfo.downloadSize ?: 0,
                    stage_progress = 0f,
                    state = DownloadState.DOWNLOAD_STATE_FAILED,
                    error_message = e.message ?: "",
                ),
            )
            close(e)
        } finally {
            activeDownloadIdsByModel.remove(modelId)
        }

        awaitClose {
            downloadLogger.debug("Download flow closed for: $modelId")
        }
    }

/**
 * Unified download helper used by all model kinds (single-file, multi-file/VLM,
 * embedding with companions). Replaces the former 3 parallel Kotlin paths by
 * composing the native primitives (`racHttpDownloadExecute`,
 * `nativeExtractArchive`, `nativeFindModelPathAfterExtraction`) that back
 * `rac_download_orchestrate` on the C++ side.
 *
 * Returns the final on-disk model path that the registry should persist.
 */
private suspend fun performDownload(
    modelId: String,
    modelInfo: ModelInfo,
    primaryUrl: String,
    emit: (DownloadProgress) -> Unit,
    logger: SDKLogger,
): String {
    // Build the list of files covering every download variant:
    //   - EMBEDDING: primary model.onnx + companion files co-located
    //   - Multi-file (VLM): each file from `multiFileDescriptors`
    //   - Single-file: one entry (the primary archive / model file)
    val targetDir = resolveDownloadTargetDir(modelId, modelInfo)
    targetDir.mkdirs()

    val downloadItems: List<DownloadItem> = buildDownloadItems(modelId, modelInfo, primaryUrl, targetDir)
    val fileCount = downloadItems.size
    val needsExtraction = fileCount == 1 && requiresExtraction(primaryUrl)

    logger.info("performDownload: $fileCount file(s), extraction=$needsExtraction, targetDir=${targetDir.absolutePath}")

    var totalBytesDownloaded = 0L
    var lastProgressEmitTime = 0L

    try {
        for ((index, item) in downloadItems.withIndex()) {
            logger.info("Downloading file ${index + 1}/$fileCount from: ${item.url}")
            logger.debug("  destination: ${item.destFile.absolutePath}")

            val fileSizeBefore = if (item.destFile.exists()) item.destFile.length() else 0L
            downloadFileWithNativeRunner(
                url = item.url,
                destFile = item.destFile,
                expectedSha256Hex = item.expectedSha256Hex,
                progressCallback = { fileProgress ->
                    val now = System.currentTimeMillis()
                    if (now - lastProgressEmitTime >= 200) {
                        lastProgressEmitTime = now
                        val combinedProgress = (index.toFloat() + fileProgress) / fileCount
                        val fileBytesRead =
                            if (item.destFile.exists()) item.destFile.length() - fileSizeBefore else 0L
                        emit(
                            DownloadProgress(
                                model_id = modelId,
                                stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
                                bytes_downloaded = totalBytesDownloaded + fileBytesRead,
                                total_bytes = modelInfo.downloadSize ?: 0,
                                stage_progress = combinedProgress,
                                state = DownloadState.DOWNLOAD_STATE_DOWNLOADING,
                            ),
                        )
                        val progressPercent = (combinedProgress * 100).toInt()
                        if (progressPercent % 5 == 0) {
                            CppBridgeEvents.emitDownloadProgress(
                                modelId,
                                combinedProgress.toDouble(),
                                totalBytesDownloaded + fileBytesRead,
                                modelInfo.downloadSize ?: 0,
                            )
                        }
                    }
                },
            )

            val writtenSize = item.destFile.length()
            if (!item.destFile.exists() || writtenSize <= 0L) {
                // Some proxies/redirects can produce success-with-0-bytes; treat as failure so
                // partial state doesn't pollute the registry.
                throw IOException(
                    "Download wrote 0 bytes for ${item.destFile.name} at ${item.destFile.absolutePath} (url=${item.url})",
                )
            }
            totalBytesDownloaded += writtenSize - fileSizeBefore
            logger.info("Completed file ${index + 1}/$fileCount: ${item.destFile.name} ($writtenSize bytes)")
        }

        // Archive extraction (single-file only). Multi-file layouts are already
        // co-located in `targetDir` and never need extraction.
        if (needsExtraction) {
            val archiveFile = downloadItems.single().destFile
            emit(
                DownloadProgress(
                    model_id = modelId,
                    stage = DownloadStage.DOWNLOAD_STAGE_EXTRACTING,
                    bytes_downloaded = totalBytesDownloaded,
                    total_bytes = totalBytesDownloaded,
                    stage_progress = 0f,
                    state = DownloadState.DOWNLOAD_STATE_EXTRACTING,
                ),
            )
            logger.info("Archive detected, extracting: ${archiveFile.absolutePath}")
            val extractedPath = extractArchive(archiveFile, modelId, logger)
            logger.info("Extraction complete: $extractedPath")
            return extractedPath
        }

        return targetDir.absolutePath
    } catch (e: Throwable) {
        // Rollback: delete partial files + clear any registry entry so cold-start
        // scans don't resurrect a half-downloaded model as "ready".
        logger.warn("Download failed for $modelId — rolling back: ${e.message}")
        runCatching {
            if (targetDir.exists()) targetDir.deleteRecursively()
        }.onFailure { cleanupErr ->
            logger.warn("Cleanup of partial files for $modelId failed: ${cleanupErr.message}")
        }
        runCatching { CppBridgeModelRegistry.remove(modelId) }
        synchronized(modelCacheLock) {
            val idx = registeredModels.indexOfFirst { it.id == modelId }
            if (idx >= 0) {
                registeredModels[idx] = registeredModels[idx].copy(localPath = null)
            }
        }
        throw e
    }
}

/** (url, destFile, expected sha-256) triple — one per file to fetch for a model. */
private data class DownloadItem(
    val url: String,
    val destFile: File,
    val expectedSha256Hex: String?,
)

/**
 * Compute the target directory where the primary + companion files land.
 *
 * All model kinds now use the canonical schema
 * `{base}/RunAnywhere/Models/{framework}/{modelId}/`. Embedding models are
 * ONNX-backed so `framework=ONNX`; the C++ RAG pipeline finds vocab.txt
 * alongside model.onnx inside that folder.
 */
private fun resolveDownloadTargetDir(modelId: String, modelInfo: ModelInfo): File {
    if (modelInfo.category == ModelCategory.EMBEDDING) {
        return File(CppBridgeModelPaths.getModelPath(modelId, CppBridgeModelRegistry.Framework.ONNX))
    }
    val framework =
        when (modelInfo.framework) {
            InferenceFramework.LLAMA_CPP -> CppBridgeModelRegistry.Framework.LLAMACPP
            InferenceFramework.ONNX -> CppBridgeModelRegistry.Framework.ONNX
            InferenceFramework.SHERPA -> CppBridgeModelRegistry.Framework.SHERPA
            InferenceFramework.FOUNDATION_MODELS -> CppBridgeModelRegistry.Framework.FOUNDATION_MODELS
            InferenceFramework.SYSTEM_TTS -> CppBridgeModelRegistry.Framework.SYSTEM_TTS
            InferenceFramework.FLUID_AUDIO -> CppBridgeModelRegistry.Framework.FLUID_AUDIO
            InferenceFramework.BUILT_IN -> CppBridgeModelRegistry.Framework.BUILTIN
            InferenceFramework.NONE -> CppBridgeModelRegistry.Framework.NONE
            InferenceFramework.GENIE -> CppBridgeModelRegistry.Framework.GENIE
            InferenceFramework.UNKNOWN -> CppBridgeModelRegistry.Framework.UNKNOWN
        }
    return File(CppBridgeModelPaths.getModelPath(modelId, framework))
}

/**
 * Build the list of [DownloadItem]s to fetch for this model.
 *
 *  - EMBEDDING: primary url → model.onnx, plus each (url, filename) companion
 *  - Multi-file (descriptors.size > 1): one entry per descriptor (per-file sha)
 *  - Single-file: one entry using the filename stem from the URL
 */
private fun buildDownloadItems(
    modelId: String,
    modelInfo: ModelInfo,
    primaryUrl: String,
    targetDir: File,
): List<DownloadItem> {
    if (modelInfo.category == ModelCategory.EMBEDDING) {
        val companions = getCompanionFiles(modelId) ?: emptyList()
        return listOf(DownloadItem(primaryUrl, File(targetDir, "model.onnx"), modelInfo.checksumSha256)) +
            companions.map { (url, filename) -> DownloadItem(url, File(targetDir, filename), null) }
    }

    val multiFileDescriptors = getMultiFileDescriptors(modelId)
    if (multiFileDescriptors != null && multiFileDescriptors.size > 1) {
        return multiFileDescriptors.map { descriptor ->
            DownloadItem(descriptor.url, File(targetDir, descriptor.filename), descriptor.checksumSha256)
        }
    }

    // Single-file: derive filename from the URL's last path segment.
    val filename =
        primaryUrl.substringAfterLast('/').substringBefore('?').ifEmpty { modelId }
    return listOf(DownloadItem(primaryUrl, File(targetDir, filename), modelInfo.checksumSha256))
}

/**
 * Check if URL requires extraction (is an archive).
 * Delegates to C++ rac_download_requires_extraction() for consistent behavior across all SDKs.
 */
private fun requiresExtraction(url: String): Boolean {
    return RunAnywhereBridge.nativeDownloadRequiresExtraction(url)
}

/**
 * Extract an archive to the model directory using native C++ extraction (libarchive).
 *
 * Supports all formats via auto-detection: ZIP, TAR.GZ, TAR.BZ2, TAR.XZ.
 * Archives typically contain a root folder (e.g., sherpa-onnx-whisper-tiny.en/)
 * so we extract to the parent directory and the archive structure creates the model folder.
 *
 * Post-extraction model path finding uses C++ rac_find_model_path_after_extraction()
 * for consistent behavior across all SDKs.
 *
 * @param archiveFile The downloaded archive file (may not have extension in filename)
 * @param modelId The model ID
 * @param logger Logger for debug output
 */
private suspend fun extractArchive(
    archiveFile: File,
    modelId: String,
    logger: SDKLogger,
): String =
    withContext(Dispatchers.IO) {
        val parentDir = archiveFile.parentFile
        if (parentDir == null || !parentDir.exists()) {
            throw SDKException.download("Cannot determine extraction directory for: ${archiveFile.absolutePath}")
        }

        logger.info("Extracting to parent: ${parentDir.absolutePath}")
        logger.debug("Archive file: ${archiveFile.absolutePath}")

        // Snapshot existing items BEFORE extraction to detect newly extracted flat files
        val itemsBeforeExtraction = parentDir.listFiles()?.map { it.name }?.toSet() ?: emptySet()

        // IMPORTANT: The archive file name might conflict with the folder inside the archive
        // (e.g., file "sherpa-onnx-whisper-tiny.en" and archive contains folder "sherpa-onnx-whisper-tiny.en/")
        // Rename archive to temp to avoid name conflicts with extracted contents / ENOTDIR errors
        val tempArchiveFile = File(parentDir, "${archiveFile.name}.tmp_archive")
        try {
            if (!archiveFile.renameTo(tempArchiveFile)) {
                archiveFile.copyTo(tempArchiveFile, overwrite = true)
                archiveFile.delete()
            }
        } catch (e: Exception) {
            throw SDKException.download("Failed to prepare archive for extraction: ${e.message}")
        }

        try {
            // Use native C++ extraction (libarchive) — auto-detects format from magic bytes
            val result =
                RunAnywhereBridge.nativeExtractArchive(
                    tempArchiveFile.absolutePath,
                    parentDir.absolutePath,
                )
            if (result != 0) {
                throw SDKException.download("Native extraction failed with code: $result")
            }
            logger.info("Native extraction completed successfully")
        } finally {
            try {
                if (tempArchiveFile.exists()) {
                    tempArchiveFile.delete()
                }
            } catch (e: Exception) {
                logger.warn("Failed to clean up temp archive: ${e.message}")
            }
        }

        // Find the extracted model directory.
        // Compute new items by comparing current contents against the pre-extraction snapshot.
        // Explicitly exclude the temp archive name in case cleanup failed (delete() returns false
        // without throwing), to avoid moving a multi-GB archive file into the model directory.
        val tempArchiveName = tempArchiveFile.name
        val expectedModelDir = File(parentDir, modelId)
        val newItems =
            parentDir
                .listFiles()
                ?.filter { it.name !in itemsBeforeExtraction && it.name != tempArchiveName }
                ?: emptyList()
        val newDirs = newItems.filter { it.isDirectory }
        val newFiles = newItems.filter { it.isFile }

        val finalPath =
            if (expectedModelDir.exists() && expectedModelDir.isDirectory) {
                // Standard case: archive root folder name matches modelId
                expectedModelDir.absolutePath
            } else if (newDirs.size == 1 && newFiles.isEmpty()) {
                // Archive had a single root directory with a different name (e.g. Genie NPU
                // tar.gz containing "llama_v3_2_1b_instruct-genie-w4-qualcomm_snapdragon_8_elite/").
                // Rename it to the expected modelId so the SDK can discover it consistently.
                val extractedDir = newDirs.first()
                if (extractedDir.renameTo(expectedModelDir)) {
                    logger.info("Renamed extracted dir '${extractedDir.name}' -> '$modelId'")
                    expectedModelDir.absolutePath
                } else {
                    logger.warn("Could not rename '${extractedDir.name}' -> '$modelId', using as-is")
                    extractedDir.absolutePath
                }
            } else {
                // Flat archive: files extracted directly into parentDir.
                // Move them into a per-model subdirectory so the SDK filesystem
                // scan can discover this model by its ID across app restarts.
                expectedModelDir.mkdirs()
                val itemsToMove = newItems.filter { it != expectedModelDir }
                var movedCount = 0
                itemsToMove.forEach { file ->
                    val dest = File(expectedModelDir, file.name)
                    if (!file.renameTo(dest)) {
                        logger.warn("Failed to move '${file.name}' into model dir, trying copy")
                        file.copyTo(dest, overwrite = true)
                        file.delete()
                    }
                    movedCount++
                }
                logger.info("Moved $movedCount flat-extracted files into: ${expectedModelDir.absolutePath}")
                expectedModelDir.absolutePath
            }

        logger.info("Model extracted to: $finalPath")
        finalPath
    }

/**
 * Download a single file via the native libcurl runner in runanywhere-commons.
 *
 * v2 close-out Phase H: replaces ~50 LOC of HttpURLConnection + redirect
 * loop. Redirects, timeouts, TLS verification, and backoff are all handled
 * by commons (`rac_http_download_execute`). Progress is reported as a
 * fraction (0.0..1.0) for parity with the old helper's signature.
 *
 * Throws [IOException] on network / HTTP / file-write / checksum failure —
 * matches the previous contract so callers don't need to know the
 * `DownloadError.*` enum.
 */
private fun downloadFileWithNativeRunner(
    url: String,
    destFile: File,
    expectedSha256Hex: String? = null,
    progressCallback: (Float) -> Unit,
) {
    destFile.parentFile?.mkdirs()

    // Prefer the install-time DownloadProvider (HttpURLConnection on Android) over
    // the libcurl-backed JNI runner. The JNI path is HTTPS-disabled on Android
    // (commons CMakeLists.txt:442-448) so it always returns INVALID_URL. Embedding
    // model download (companion-file flow) used to skip the provider check; this
    // unifies it with the regular single-file flow in CppBridgeDownload.
    CppBridgeDownload.downloadProvider?.let { provider ->
        val ok =
            provider.download(url, destFile.absolutePath) { bytes, total ->
                if (total > 0) progressCallback(bytes.toFloat() / total.toFloat())
            }
        if (!ok) {
            throw IOException("Download failed for $url (DownloadProvider returned false)")
        }
        return
    }

    val listener =
        com.runanywhere.sdk.native.bridge.NativeDownloadProgressListener { bytes, total ->
            if (total > 0) {
                progressCallback(bytes.toFloat() / total.toFloat())
            }
            true
        }
    val outStatus = IntArray(1)
    val rc =
        RunAnywhereBridge.racHttpDownloadExecute(
            url = url,
            destPath = destFile.absolutePath,
            expectedSha256Hex = expectedSha256Hex,
            resumeFromByte = 0L,
            timeoutMs = 120_000,
            listener = listener,
            outHttpStatus = outStatus,
        )
    if (rc != CppBridgeDownload.DownloadError.NONE) {
        throw IOException(
            "Download failed for $url: ${CppBridgeDownload.DownloadError.getName(rc)} " +
                "(http_status=${outStatus[0]})",
        )
    }
}

actual suspend fun RunAnywhere.cancelDownload(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val activeDownloadId = activeDownloadIdsByModel.remove(modelId)
    if (activeDownloadId != null) {
        CppBridgeDownload.cancelDownload(activeDownloadId)
    }
    CppBridgeModelRegistry.updateDownloadStatus(modelId, null)
}

actual suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val model = CppBridgeModelRegistry.get(modelId) ?: return false
    return model.localPath != null && model.localPath.isNotEmpty()
}

actual suspend fun RunAnywhere.deleteModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeStorage.delete(CppBridgeStorage.StorageNamespace.DOWNLOADS, modelId)
    CppBridgeModelRegistry.remove(modelId)
}

actual suspend fun RunAnywhere.deleteAllModels() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val downloaded = CppBridgeModelRegistry.getDownloaded()
    downloaded.forEach { model ->
        val localPath = model.localPath
        if (!localPath.isNullOrEmpty()) {
            runCatching { File(localPath).deleteRecursively() }
                .onFailure { modelsLogger.warning("Failed to delete ${model.modelId} at $localPath: ${it.message}") }
        }
        CppBridgeStorage.delete(CppBridgeStorage.StorageNamespace.DOWNLOADS, model.modelId)
        CppBridgeModelRegistry.updateDownloadStatus(model.modelId, null)
    }
    synchronized(modelCacheLock) {
        registeredModels.replaceAll { it.copy(localPath = null) }
    }
}

actual suspend fun RunAnywhere.refreshModelRegistry(
    includeRemoteCatalog: Boolean,
    rescanLocal: Boolean,
    pruneOrphans: Boolean,
) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    modelsLogger.info("Refreshing model registry via rac_model_registry_refresh")
    val rc =
        RunAnywhereBridge.racModelRegistryRefresh(
            includeRemoteCatalog = includeRemoteCatalog,
            rescanLocal = rescanLocal,
            pruneOrphans = pruneOrphans,
        )
    if (rc != 0) {
        modelsLogger.warning("refreshModelRegistry returned non-zero rc=$rc")
    }
}

actual suspend fun RunAnywhere.loadModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val model =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKException.model("Model '$modelId' not found in registry")
    // Route to the type-specific loader based on registered category.
    when (model.category) {
        CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION -> loadSTTModel(modelId)
        CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS -> loadTTSModel(modelId)
        else -> loadLLMModel(modelId)
    }
}

actual suspend fun RunAnywhere.loadLLMModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val model =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKException.model("Model '$modelId' not found in registry")

    val localPath =
        model.localPath
            ?: throw SDKException.model("Model '$modelId' is not downloaded")

    // Pass modelPath, modelId, and modelName separately for correct telemetry
    val result = CppBridgeLLM.loadModel(localPath, modelId, model.name)
    if (result != 0) {
        throw SDKException.llm("Failed to load LLM model '$modelId' (error code: $result)")
    }
}

actual suspend fun RunAnywhere.unloadLLMModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeLLM.unload()
}

actual val RunAnywhere.isLLMModelLoaded: Boolean
    get() = CppBridgeLLM.isLoaded

// Round 1 KOTLIN (G-A8): `currentLLMModelId` deleted — callers use
// `currentLLMModel?.id` for the legacy ID-only access pattern.

actual val RunAnywhere.currentLLMModel: ModelInfo?
    get() {
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
        throw SDKException.notInitialized("SDK not initialized")
    }

    val model =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKException.model("Model '$modelId' not found in registry")

    val localPath =
        model.localPath
            ?: throw SDKException.model("Model '$modelId' is not downloaded")

    // Run native load on IO thread to avoid ANR and native crashes on main thread
    val result =
        withContext(Dispatchers.IO) {
            val dir = File(localPath)
            if (!dir.exists()) {
                return@withContext -1
            }
            if (!dir.isDirectory) {
                modelsLogger.error("STT model path is not a directory (expected extracted model dir): $localPath")
                return@withContext -1
            }
            // C++ backend (sherpa_backend.cpp SherpaSTT::load_model) globs the
            // directory for *encoder*.onnx, *decoder*.onnx, *tokens*.txt — the
            // Sherpa-ONNX upstream archives use prefixed names like
            // `tiny.en-encoder.onnx` / `tiny.en-encoder.int8.onnx`. We match
            // the same substring rule here so the pre-check accepts every
            // archive layout the native loader can actually consume.
            val files = dir.listFiles().orEmpty()
            val hasEncoder = files.any { it.name.contains("encoder") && it.name.endsWith(".onnx") }
            val hasDecoder = files.any { it.name.contains("decoder") && it.name.endsWith(".onnx") }
            val hasTokens = files.any { it.name == "tokens.txt" || (it.name.contains("tokens") && it.name.endsWith(".txt")) }
            val hasSingleFileCtc = files.any { it.name == "model.onnx" || it.name == "model.int8.onnx" }
            // Whisper / transducer models need both encoder + decoder; NeMo CTC
            // ships a single `model.onnx` (or quantized variant) with tokens.
            val hasUsableLayout = (hasEncoder && hasDecoder && hasTokens) || (hasSingleFileCtc && hasTokens)
            if (!hasUsableLayout) {
                modelsLogger.error(
                    "STT model directory missing required files at $localPath. " +
                        "Expected either (*encoder*.onnx + *decoder*.onnx + *tokens*.txt) " +
                        "or (model.onnx|model.int8.onnx + tokens.txt). Re-download the model.",
                )
                return@withContext -1
            }
            CppBridgeSTT.loadModel(localPath, modelId, model.name)
        }
    if (result != 0) {
        throw SDKException.stt(
            "Failed to load STT model '$modelId' (error code: $result). " +
                "Ensure the model is extracted and contains either an *encoder*.onnx + *decoder*.onnx + *tokens*.txt " +
                "set (Whisper / transducer) or a model.onnx + tokens.txt pair (NeMo CTC).",
        )
    }
}

// ============================================================================
// MODEL ASSIGNMENTS API
// ============================================================================

/**
 * Fetch model assignments for the current device from the backend.
 *
 * This method fetches models assigned to this device based on device type and platform.
 * Results are cached and saved to the model registry automatically.
 *
 * Note: Model assignments are automatically fetched during SDK initialization
 * when services are initialized (Phase 2). This method allows manual refresh.
 *
 * @param forceRefresh If true, bypass cache and fetch fresh data from backend
 * @return List of ModelInfo objects assigned to this device
 */
actual suspend fun RunAnywhere.fetchModelAssignments(forceRefresh: Boolean): List<ModelInfo> =
    withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        ensureServicesReady()

        modelsLogger.info("Fetching model assignments (forceRefresh=$forceRefresh)...")

        try {
            val jsonResult =
                com.runanywhere.sdk.foundation.bridge.extensions
                    .CppBridgeModelAssignment
                    .fetchModelAssignments(forceRefresh)

            // Parse JSON result to ModelInfo list
            val models = parseModelAssignmentsJson(jsonResult)
            modelsLogger.info("Fetched ${models.size} model assignments")
            models
        } catch (e: Exception) {
            modelsLogger.error("Failed to fetch model assignments: ${e.message}")
            emptyList()
        }
    }

/**
 * Parse model assignments JSON into [ModelInfo]s.
 *
 * M3: replaced a 117-LOC hand-rolled regex parser with `kotlinx.serialization`.
 * `rac_model_assignment_fetch` still returns a JSON array so the server shape
 * is unchanged; Kotlin decodes into [ModelAssignmentDto]s and maps each to the
 * public `ModelInfo`. The old `categoryInt` truncation (only 0–3 mapped, 4–7
 * silently fell through to LANGUAGE) is fixed by using the full
 * [ModelCategory] enum range.
 */
private fun parseModelAssignmentsJson(json: String): List<ModelInfo> {
    if (json.isEmpty() || json == "[]") return emptyList()
    return try {
        val dtos = modelAssignmentJson.decodeFromString<List<ModelAssignmentDto>>(json)
        dtos.map { it.toModelInfo() }
    } catch (e: Exception) {
        modelsLogger.error("Failed to parse model assignments JSON: ${e.message}")
        emptyList()
    }
}

/** Lenient JSON parser — ignores server-side field additions we don't know about. */
private val modelAssignmentJson = kotlinx.serialization.json.Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
}

/**
 * Wire shape of one element in the JSON array returned by
 * `rac_model_assignment_fetch`. Kept as an internal-only DTO so the public
 * `ModelInfo` stays hand-written (it carries more than the wire shape:
 * artifact type, capability flags, etc.).
 */
@kotlinx.serialization.Serializable
private data class ModelAssignmentDto(
    val id: String,
    val name: String? = null,
    val category: Int = 0,
    val format: Int = 0,
    val framework: Int = 0,
    val downloadUrl: String? = null,
    val downloadSize: Long = 0,
    val contextLength: Int = 0,
    val supportsThinking: Boolean = false,
) {
    fun toModelInfo(): ModelInfo =
        ModelInfo(
            id = id,
            name = name ?: id,
            category =
                // Full ModelCategory range — fixes the old 0..3 truncation that
                // silently dropped VISION / MULTIMODAL / IMAGE_GENERATION / EMBEDDING.
                when (category) {
                    CppBridgeModelRegistry.ModelCategory.LANGUAGE -> ModelCategory.LANGUAGE
                    CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION -> ModelCategory.SPEECH_RECOGNITION
                    CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS -> ModelCategory.SPEECH_SYNTHESIS
                    CppBridgeModelRegistry.ModelCategory.AUDIO -> ModelCategory.AUDIO
                    CppBridgeModelRegistry.ModelCategory.VISION -> ModelCategory.VISION
                    CppBridgeModelRegistry.ModelCategory.MULTIMODAL -> ModelCategory.MULTIMODAL
                    CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION -> ModelCategory.IMAGE_GENERATION
                    CppBridgeModelRegistry.ModelCategory.EMBEDDING -> ModelCategory.EMBEDDING
                    else -> ModelCategory.LANGUAGE
                },
            format =
                when (format) {
                    CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
                    CppBridgeModelRegistry.ModelFormat.ORT -> ModelFormat.ORT
                    CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
                    CppBridgeModelRegistry.ModelFormat.BIN -> ModelFormat.BIN
                    CppBridgeModelRegistry.ModelFormat.QNN_CONTEXT -> ModelFormat.QNN_CONTEXT
                    else -> ModelFormat.UNKNOWN
                },
            framework =
                when (framework) {
                    CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.LLAMA_CPP
                    CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.ONNX
                    CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.FOUNDATION_MODELS
                    CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.SYSTEM_TTS
                    CppBridgeModelRegistry.Framework.GENIE -> InferenceFramework.GENIE
                    else -> InferenceFramework.UNKNOWN
                },
            downloadURL = downloadUrl,
            localPath = null,
            downloadSize = if (downloadSize > 0) downloadSize else null,
            contextLength = if (contextLength > 0) contextLength else null,
            supportsThinking = supportsThinking,
            description = null,
        )
}
