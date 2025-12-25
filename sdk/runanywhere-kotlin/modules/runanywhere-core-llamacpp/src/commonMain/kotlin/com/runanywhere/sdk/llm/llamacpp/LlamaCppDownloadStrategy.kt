package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.download.DownloadStrategy
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * Download strategy for LlamaCPP models (.gguf, .ggml files)
 *
 * Handles simple direct file downloads - no archive extraction needed.
 * GGUF models are single files that can be downloaded directly.
 */
class LlamaCppDownloadStrategy : DownloadStrategy, ModelStorageStrategy {
    private val logger = SDKLogger("LlamaCppDownloadStrategy")

    // MARK: - DownloadStrategy

    override fun canHandle(model: ModelInfo): Boolean {
        // Must be LlamaCPP compatible
        if (!model.compatibleFrameworks.contains(InferenceFramework.LLAMA_CPP)) {
            return false
        }

        val urlString = model.downloadURL ?: return false
        val lowercased = urlString.lowercase()

        return lowercased.endsWith(".gguf") ||
            lowercased.endsWith(".ggml") ||
            lowercased.contains("gguf") ||
            lowercased.contains("ggml")
    }

    override suspend fun download(
        model: ModelInfo,
        to: String,
        progressHandler: ((Double) -> Unit)?
    ): String {
        logger.info("Downloading GGUF model: ${model.id}")

        val downloadURL = model.downloadURL
            ?: throw IllegalArgumentException("Model ${model.id} has no download URL")

        // Create destination folder
        createDirectory(to)

        // Download directly - GGUF models are single files
        val modelPath = downloadGGUFFile(downloadURL, model.id, to, progressHandler)

        logger.info("GGUF model downloaded to: $modelPath")
        return modelPath
    }

    // MARK: - ModelStorageStrategy

    override fun findModelPath(modelId: String, modelFolder: String): String? {
        return findGGUFModelPath(modelId, modelFolder)
    }

    override fun detectModel(modelFolder: String): Pair<ModelFormat, Long>? {
        return detectGGUFModel(modelFolder)
    }

    override fun isValidModelStorage(modelFolder: String): Boolean {
        return isValidGGUFModelStorage(modelFolder)
    }

    companion object {
        val shared = LlamaCppDownloadStrategy()
    }
}

// MARK: - Platform-specific implementations (expect declarations)

/**
 * Download a GGUF file from URL to destination folder
 */
internal expect suspend fun downloadGGUFFile(
    url: String,
    modelId: String,
    destinationFolder: String,
    progressHandler: ((Double) -> Unit)?
): String

/**
 * Create a directory
 */
internal expect fun createDirectory(path: String)

/**
 * Find GGUF model path in a folder
 */
internal expect fun findGGUFModelPath(modelId: String, folder: String): String?

/**
 * Detect GGUF model in folder
 */
internal expect fun detectGGUFModel(folder: String): Pair<ModelFormat, Long>?

/**
 * Check if folder contains valid GGUF model
 */
internal expect fun isValidGGUFModelStorage(folder: String): Boolean
