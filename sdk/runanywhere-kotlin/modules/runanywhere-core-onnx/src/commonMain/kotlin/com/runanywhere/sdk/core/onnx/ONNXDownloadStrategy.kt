package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.core.frameworks.DownloadStrategy
import com.runanywhere.sdk.core.frameworks.ModelStorageStrategy
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Download strategy for ONNX models
 * Handles downloading .onnx files and .tar.bz2 archives
 *
 * Matches iOS ONNXDownloadStrategy
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXDownloadStrategy.swift
 */
class ONNXDownloadStrategy : DownloadStrategy, ModelStorageStrategy {

    private val logger = SDKLogger("ONNXDownloadStrategy")

    // MARK: - DownloadStrategy Implementation

    /**
     * Check if this strategy can handle the model
     * Supports .onnx files and .tar.bz2 archives with ONNX framework
     */
    override fun canHandle(model: ModelInfo): Boolean {
        // Must be ONNX compatible
        if (!model.compatibleFrameworks.contains(LLMFramework.ONNX)) {
            return false
        }

        // Check URL extension
        val urlString = model.downloadURL ?: return false
        val lowercased = urlString.lowercase()

        return lowercased.endsWith(".onnx") ||
                lowercased.endsWith(".tar.bz2") ||
                lowercased.endsWith(".tar.gz") ||
                lowercased.contains("onnx")
    }

    /**
     * Download the model to the destination folder
     */
    override suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?
    ): String {
        logger.info("Downloading ONNX model: ${model.id}")

        val downloadURL = model.downloadURL
            ?: throw ONNXError.ModelNotFound(model.id)

        val lowercased = downloadURL.lowercase()

        return when {
            lowercased.endsWith(".tar.bz2") || lowercased.endsWith(".tar.gz") -> {
                downloadArchive(downloadURL, destinationFolder, progressHandler)
            }
            lowercased.endsWith(".onnx") -> {
                downloadDirectONNX(downloadURL, model.id, destinationFolder, progressHandler)
            }
            else -> {
                // Default to direct download
                downloadDirectONNX(downloadURL, model.id, destinationFolder, progressHandler)
            }
        }
    }

    // MARK: - ModelStorageStrategy Implementation

    /**
     * Find model path for a given model ID in the folder
     * Handles nested directory structures (common with sherpa-onnx)
     */
    override fun findModelPath(modelId: String, modelFolder: String): String? {
        return findONNXModelPath(modelId, modelFolder)
    }

    /**
     * Detect model format and size in the folder
     */
    override fun detectModel(modelFolder: String): Pair<ModelFormat, Long>? {
        return detectONNXModel(modelFolder)
    }

    /**
     * Check if the folder contains valid model storage
     */
    override fun isValidModelStorage(modelFolder: String): Boolean {
        return isValidONNXModelStorage(modelFolder)
    }

    // MARK: - Private Methods

    /**
     * Download and extract archive (e.g., .tar.bz2 from sherpa-onnx)
     *
     * Process:
     * 1. Download archive to temp location
     * 2. Extract to destination folder
     * 3. Find model directory in extracted contents
     * 4. Return path to model directory (not individual .onnx file for multi-file models)
     */
    private suspend fun downloadArchive(
        url: String,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?
    ): String {
        logger.info("Downloading archive from: $url to $destinationFolder")

        // Create destination folder
        createDirectory(destinationFolder)

        // Download the archive to a temp file within the destination folder
        // This ensures we can extract to the same filesystem (avoid cross-device issues)
        val archivePath = downloadFile(url, destinationFolder) { progress ->
            // Scale progress: 0-50% for download
            progressHandler?.invoke(progress * 0.5)
        }
        logger.info("Archive downloaded to: $archivePath")

        // Report extraction starting
        progressHandler?.invoke(0.55)

        // Extract the archive to destination folder
        logger.info("Extracting archive to: $destinationFolder")
        val extractedPath = extractArchive(archivePath, destinationFolder)
        logger.info("Archive extracted to: $extractedPath")

        // Report extraction progress
        progressHandler?.invoke(0.9)

        // Find the model within extracted contents
        // For sherpa-onnx models, this returns the DIRECTORY containing encoder.onnx, decoder.onnx, tokens.txt
        val modelPath = findONNXModelPath("", extractedPath)
            ?: throw ONNXError.ModelLoadFailed("No ONNX model found in extracted archive at $extractedPath")

        logger.info("Found model at: $modelPath")
        progressHandler?.invoke(1.0)

        return modelPath
    }

    /**
     * Download direct .onnx file and companion config
     */
    private suspend fun downloadDirectONNX(
        url: String,
        modelId: String,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?
    ): String {
        logger.info("Downloading ONNX file from: $url")

        // Create model directory
        val modelDir = "$destinationFolder/$modelId"
        createDirectory(modelDir)

        // Download the main model file
        val modelPath = downloadFile(url, modelDir, progressHandler)

        // Try to download companion config file (model.onnx -> model.onnx.json)
        val configUrl = "$url.json"
        try {
            downloadFile(configUrl, modelDir, null)
            logger.debug("Downloaded companion config file")
        } catch (e: Exception) {
            logger.debug("No companion config file found (optional)")
        }

        return modelPath
    }

    companion object {
        /**
         * Singleton instance
         */
        val shared = ONNXDownloadStrategy()
    }
}

// Platform-specific implementations (expect declarations)

/**
 * Download a file from URL to destination folder
 * @return Path to the downloaded file
 */
expect suspend fun downloadFile(
    url: String,
    destinationFolder: String,
    progressHandler: ((Double) -> Unit)?
): String

/**
 * Extract an archive to destination folder
 * @return Path to extracted contents
 */
expect suspend fun extractArchive(archivePath: String, destinationFolder: String): String

/**
 * Create a directory
 */
expect fun createDirectory(path: String)

/**
 * Find ONNX model path in a folder (recursive up to 2 levels)
 */
expect fun findONNXModelPath(modelId: String, folder: String): String?

/**
 * Detect ONNX model in folder
 */
expect fun detectONNXModel(folder: String): Pair<ModelFormat, Long>?

/**
 * Check if folder contains valid ONNX model
 */
expect fun isValidONNXModelStorage(folder: String): Boolean
