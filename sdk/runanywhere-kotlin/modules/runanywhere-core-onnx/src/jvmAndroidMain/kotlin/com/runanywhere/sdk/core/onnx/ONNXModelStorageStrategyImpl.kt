package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.storage.ModelStorageStrategy
import com.runanywhere.sdk.models.enums.ModelFormat
import java.io.File

/**
 * JVM/Android implementation of ONNX model storage strategy
 * Handles detection of ONNX models including Sherpa-ONNX nested directory structures
 *
 * Matches iOS ONNXDownloadStrategy.ModelStorageStrategy implementation
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXDownloadStrategy.swift
 */
actual class ONNXModelStorageStrategy actual constructor() : ModelStorageStrategy {

    /**
     * Find the model path within a model folder
     * Handles both direct .onnx files and nested sherpa-onnx structures
     *
     * @param modelId The model identifier
     * @param modelFolder The base folder to search in
     * @return Path to the model if found, null otherwise
     */
    actual override fun findModelPath(modelId: String, modelFolder: String): String? {
        val folder = File(modelFolder)

        // Check if folder exists
        if (!folder.exists() || !folder.isDirectory) {
            return null
        }

        // First check if the folder itself is a valid model directory
        if (isValidModelStorage(modelFolder)) {
            return modelFolder
        }

        // Check for nested subdirectory (sherpa-onnx tar.bz2 structure)
        // e.g., sherpa-whisper-tiny-onnx/sherpa-onnx-whisper-tiny.en/
        val subdirs = folder.listFiles()?.filter { it.isDirectory } ?: emptyList()
        for (subdir in subdirs) {
            if (isValidModelStorage(subdir.absolutePath)) {
                return subdir.absolutePath
            }
        }

        // Check for direct .onnx file
        val onnxFile = findOnnxFile(folder)
        if (onnxFile != null) {
            return modelFolder
        }

        return null
    }

    /**
     * Detect model format and size in the folder
     * @return Pair of (format, size in bytes) or null if not found
     */
    actual override fun detectModel(modelFolder: String): Pair<ModelFormat, Long>? {
        if (!isValidModelStorage(modelFolder)) {
            return null
        }

        val size = calculateDirectorySize(File(modelFolder))
        return Pair(ModelFormat.ONNX, size)
    }

    /**
     * Check if the folder contains valid ONNX model storage
     * Supports:
     * - Sherpa-ONNX Whisper structure (encoder.onnx, decoder.onnx, tokens.txt)
     * - Single .onnx file models
     */
    actual override fun isValidModelStorage(modelFolder: String): Boolean {
        val folder = File(modelFolder)
        if (!folder.exists() || !folder.isDirectory) {
            return false
        }

        val files = folder.listFiles()?.map { it.name } ?: return false

        // Check for Sherpa-ONNX Whisper structure
        val hasEncoder = files.any { it.contains("encoder") && it.endsWith(".onnx") }
        val hasDecoder = files.any { it.contains("decoder") && it.endsWith(".onnx") }
        val hasTokens = files.any { it.contains("tokens") && it.endsWith(".txt") }

        if (hasEncoder && hasDecoder && hasTokens) {
            return true
        }

        // Check for single ONNX model file
        val hasOnnxFile = files.any { it.endsWith(".onnx") }
        return hasOnnxFile
    }

    /**
     * Find .onnx file in a directory (non-recursive)
     */
    private fun findOnnxFile(folder: File): File? {
        return folder.listFiles()?.firstOrNull { it.extension == "onnx" }
    }

    /**
     * Find .onnx file recursively (up to 2 levels deep)
     */
    private fun findOnnxFileRecursive(folder: File, depth: Int = 0): File? {
        val maxDepth = 2
        if (depth > maxDepth || !folder.exists()) return null

        // First check for .onnx files at this level
        val onnxFile = folder.listFiles()?.firstOrNull { it.extension == "onnx" }
        if (onnxFile != null) return onnxFile

        // Then recursively check subdirectories
        folder.listFiles()?.filter { it.isDirectory }?.forEach { subdir ->
            val found = findOnnxFileRecursive(subdir, depth + 1)
            if (found != null) return found
        }

        return null
    }

    /**
     * Calculate total size of a directory
     */
    private fun calculateDirectorySize(folder: File): Long {
        if (!folder.exists()) return 0L

        return folder.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }
}
