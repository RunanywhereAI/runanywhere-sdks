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

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAAdapterInfo
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (G-A7): canonical `RunAnywhere.lora.*` namespace.
//
// Per canonical §3 LoRA section: 8 methods exposed under a `LoRA` capability
// object. The pre-existing flat extensions (loadLoraAdapter, etc.) remain so
// existing call sites compile, but the namespaced form is the canonical
// surface that mirrors Swift / RN / Web / Flutter.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Capability namespace for LoRA adapter management.
 *
 * Per canonical §3 — 8 method surface:
 * `lora.load`, `lora.remove`, `lora.clear`, `lora.getLoaded`,
 * `lora.checkCompatibility`, `lora.register`, `lora.adaptersForModel`,
 * `lora.allRegistered`.
 */
expect class LoRA internal constructor() {
    /** Load and apply a LoRA adapter, returning the loaded info snapshot. */
    suspend fun load(config: LoRAAdapterConfig): LoRAAdapterInfo

    /** Remove a previously-loaded adapter by id. */
    suspend fun remove(adapterId: String)

    /** Clear all currently-loaded adapters. */
    suspend fun clear()

    /** Snapshot of all currently-loaded adapters. */
    suspend fun getLoaded(): List<LoRAAdapterInfo>

    /** Pre-flight compatibility check between an adapter id and base model id. */
    suspend fun checkCompatibility(adapterId: String, modelId: String): LoraCompatibilityResult

    /** Register an adapter in the catalog so [adaptersForModel] / [allRegistered] can find it. */
    suspend fun register(config: LoRAAdapterConfig)

    /** Adapters in the catalog compatible with the supplied base model id. */
    suspend fun adaptersForModel(modelId: String): List<LoRAAdapterInfo>

    /** Snapshot of every adapter currently registered in the catalog. */
    suspend fun allRegistered(): List<LoRAAdapterInfo>
}

/** Public capability accessor — `RunAnywhere.lora.load(config)`. */
expect val RunAnywhere.lora: LoRA

// MARK: - LoRA Adapter Management

/**
 * Load and apply a LoRA adapter to the currently loaded model.
 *
 * The adapter is loaded from a GGUF file and applied with the given scale.
 * Multiple adapters can be stacked. Context is recreated internally.
 *
 * @param config LoRA adapter configuration (path and scale)
 * @throws SDKException if no model is loaded or loading fails
 */
expect suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig)

/**
 * Remove a specific LoRA adapter by path.
 *
 * @param path Path that was used when loading the adapter
 * @throws SDKException if adapter not found or removal fails
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
//
// Round 1 KOTLIN (G-B2 / Task 5): hand-rolled `LoraCompatibilityResult` DELETED.
// The proto-generated `ai.runanywhere.proto.v1.LoraCompatibilityResult` is the
// canonical type. `checkLoraCompatibility` now returns the proto type directly.

/**
 * Check if a LoRA adapter file is compatible with the currently loaded model.
 *
 * @param loraPath Path to the LoRA adapter GGUF file
 * @return [ai.runanywhere.proto.v1.LoraCompatibilityResult] with [is_compatible]
 *         and optional [error_message].
 */
expect fun RunAnywhere.checkLoraCompatibility(loraPath: String): ai.runanywhere.proto.v1.LoraCompatibilityResult

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
    /**
     * Optional lowercase hex SHA-256 checksum of the adapter file.
     * When populated, the native download runner verifies the hash
     * inline and fails with `RAC_HTTP_DL_CHECKSUM_FAILED` on mismatch.
     */
    val checksumSha256: String? = null,
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
 * @throws SDKException if adapter not found or download fails
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
