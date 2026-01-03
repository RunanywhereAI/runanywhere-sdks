/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for model management operations.
 * Calls C++ directly via CppBridge.ModelRegistry for all operations.
 *
 * Mirrors Swift RunAnywhere+ModelManagement.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.coroutines.flow.Flow

// MARK: - Model Discovery

/**
 * Get all available models (both downloaded and remote).
 *
 * @return List of all model info
 */
expect suspend fun RunAnywhere.availableModels(): List<ModelInfo>

/**
 * Get models by category.
 *
 * @param category Model category to filter by
 * @return List of models in the specified category
 */
expect suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

/**
 * Get downloaded models.
 *
 * @return List of downloaded model info
 */
expect suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>

/**
 * Get model info by ID.
 *
 * @param modelId Model identifier
 * @return Model info or null if not found
 */
expect suspend fun RunAnywhere.model(modelId: String): ModelInfo?

// MARK: - Model Downloads

/**
 * Download a model.
 *
 * @param modelId Model identifier to download
 * @return Flow of download progress
 */
expect fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress>

/**
 * Cancel a model download.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.cancelDownload(modelId: String)

/**
 * Check if a model is downloaded.
 *
 * @param modelId Model identifier
 * @return True if the model is downloaded
 */
expect suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean

// MARK: - Model Management

/**
 * Delete a downloaded model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.deleteModel(modelId: String)

/**
 * Delete all downloaded models.
 */
expect suspend fun RunAnywhere.deleteAllModels()

/**
 * Refresh the model registry from remote.
 */
expect suspend fun RunAnywhere.refreshModelRegistry()

// MARK: - Model Loading

/**
 * Load an LLM model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.loadLLMModel(modelId: String)

/**
 * Unload the currently loaded LLM model.
 */
expect suspend fun RunAnywhere.unloadLLMModel()

/**
 * Check if an LLM model is loaded.
 *
 * @return True if a model is loaded
 */
expect suspend fun RunAnywhere.isLLMModelLoaded(): Boolean

/**
 * Load an STT model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.loadSTTModel(modelId: String)
