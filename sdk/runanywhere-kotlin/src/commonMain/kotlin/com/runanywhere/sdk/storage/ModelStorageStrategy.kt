package com.runanywhere.sdk.storage

import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Model storage strategy interface matching iOS ModelStorageStrategy protocol.
 * Provides methods for detecting and locating models on disk.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Frameworks/UnifiedFrameworkAdapter.swift
 */
interface ModelStorageStrategy {
    /**
     * Find model path for a given model ID in the folder
     * @param modelId The model identifier
     * @param modelFolder The folder to search in
     * @return Path to the model if found, null otherwise
     */
    fun findModelPath(
        modelId: String,
        modelFolder: String,
    ): String?

    /**
     * Detect model format and size in the folder
     * @param modelFolder The folder to examine
     * @return Pair of (format, size in bytes) or null if not found
     */
    fun detectModel(modelFolder: String): Pair<ModelFormat, Long>?

    /**
     * Check if the folder contains valid model storage
     * @param modelFolder The folder to validate
     * @return true if storage is valid and complete
     */
    fun isValidModelStorage(modelFolder: String): Boolean
}
