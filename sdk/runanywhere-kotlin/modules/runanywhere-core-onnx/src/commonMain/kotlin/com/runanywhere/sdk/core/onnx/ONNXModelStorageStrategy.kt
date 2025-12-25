package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * ONNX-specific model storage strategy
 * Handles detection of ONNX models including Sherpa-ONNX nested directory structures
 *
 * Matches iOS ONNXDownloadStrategy.ModelStorageStrategy implementation
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXDownloadStrategy.swift
 */
expect class ONNXModelStorageStrategy() : ModelStorageStrategy {
    /**
     * Find the model path within a model folder
     * Handles both direct .onnx files and nested sherpa-onnx structures
     */
    override fun findModelPath(modelId: String, modelFolder: String): String?

    /**
     * Detect model format and size in the folder
     */
    override fun detectModel(modelFolder: String): Pair<ModelFormat, Long>?

    /**
     * Check if the folder contains valid ONNX model storage
     */
    override fun isValidModelStorage(modelFolder: String): Boolean
}
