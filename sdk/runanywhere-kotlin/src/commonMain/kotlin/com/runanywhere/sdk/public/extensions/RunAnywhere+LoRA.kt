/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for LoRA adapter management.
 * Delegates to C++ via CppBridgeLLM for all operations.
 *
 * LoRA (Low-Rank Adaptation) adapters allow fine-tuning behavior
 * of a loaded base model without replacing it.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import kotlinx.coroutines.flow.Flow

// MARK: - LoRA Adapter Management

/**
 * Load and apply a LoRA adapter to the currently loaded model.
 *
 * The adapter is loaded from a GGUF file and applied with the given scale.
 * Multiple adapters can be stacked. Context is recreated internally.
 *
 * @param config LoRA adapter configuration (path and scale)
 * @throws SDKError if no model is loaded or loading fails
 */
expect suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig)

/**
 * Remove a specific LoRA adapter by path.
 *
 * @param path Path that was used when loading the adapter
 * @throws SDKError if adapter not found or removal fails
 */
expect suspend fun RunAnywhere.removeLoraAdapter(path: String)

/**
 * Remove all loaded LoRA adapters.
 */
expect suspend fun RunAnywhere.clearLoraAdapters()

/**
 * Get info about all currently loaded LoRA adapters.
 *
 * @return List of loaded adapter info (path, scale, applied status)
 */
expect suspend fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterInfo>

// MARK: - LoRA Compatibility Check

/**
 * Result of a LoRA compatibility check.
 */
data class LoraCompatibilityResult(
    val isCompatible: Boolean,
    val error: String? = null,
)

/**
 * Check if a LoRA adapter file is compatible with the currently loaded model.
 *
 * @param loraPath Path to the LoRA adapter GGUF file
 * @return Compatibility result with error message if incompatible
 */
expect fun RunAnywhere.checkLoraCompatibility(loraPath: String): LoraCompatibilityResult

// MARK: - LoRA Adapter Catalog (Registry)

/**
 * A LoRA adapter entry in the catalog registry.
 * Contains metadata about a LoRA adapter and its compatible base models.
 */
data class LoraAdapterCatalogEntry(
    val id: String,
    val name: String,
    val description: String,
    val downloadUrl: String,
    val filename: String,
    val compatibleModelIds: List<String>,
    val fileSize: Long = 0,
    val defaultScale: Float = 1.0f,
)

/**
 * Register a LoRA adapter in the catalog.
 * The adapter metadata is stored in the C++ LoRA registry.
 *
 * @param entry The adapter catalog entry with metadata
 */
expect fun RunAnywhere.registerLoraAdapter(entry: LoraAdapterCatalogEntry)

/**
 * Get LoRA adapters compatible with a specific model.
 *
 * @param modelId The base model ID to find adapters for
 * @return List of compatible adapter catalog entries
 */
expect fun RunAnywhere.loraAdaptersForModel(modelId: String): List<LoraAdapterCatalogEntry>

/**
 * Get all registered LoRA adapters.
 *
 * @return List of all adapter catalog entries
 */
expect fun RunAnywhere.allRegisteredLoraAdapters(): List<LoraAdapterCatalogEntry>

// MARK: - LoRA Adapter Downloads

/**
 * Download a LoRA adapter GGUF file by its registered catalog ID.
 * Returns a Flow of download progress matching the model download pattern.
 *
 * @param adapterId Adapter ID from the catalog registry
 * @return Flow of download progress events
 * @throws SDKError if adapter not found or download fails
 */
expect fun RunAnywhere.downloadLoraAdapter(adapterId: String): Flow<DownloadProgress>

/**
 * Get the local file path for a downloaded LoRA adapter.
 *
 * @param adapterId Adapter ID from the catalog registry
 * @return Absolute file path if downloaded, null otherwise
 */
expect fun RunAnywhere.loraAdapterLocalPath(adapterId: String): String?

/**
 * Delete a downloaded LoRA adapter file from disk.
 *
 * @param adapterId Adapter ID from the catalog registry
 * @return true if file was deleted, false if not found
 */
expect fun RunAnywhere.deleteDownloadedLoraAdapter(adapterId: String): Boolean
