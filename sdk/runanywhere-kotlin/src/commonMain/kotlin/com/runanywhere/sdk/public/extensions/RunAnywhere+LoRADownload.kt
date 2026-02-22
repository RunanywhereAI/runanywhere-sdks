/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for downloading LoRA adapters.
 * Supports downloading from external URLs and from the built-in catalog.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.temp.LoraAdapterCatalog
import com.runanywhere.sdk.temp.LoraAdapterEntry
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable

// MARK: - LoRA Download Types

/**
 * State of a LoRA adapter download.
 */
@Serializable
enum class LoraDownloadState {
    PENDING,
    DOWNLOADING,
    COMPLETED,
    ERROR,
}

/**
 * Progress information for a LoRA adapter download.
 */
@Serializable
data class LoraDownloadProgress(
    /** Download progress (0.0 to 1.0) */
    val progress: Float,
    /** Bytes downloaded so far */
    val bytesDownloaded: Long,
    /** Total bytes (null if unknown) */
    val totalBytes: Long?,
    /** Current download state */
    val state: LoraDownloadState,
    /** Local file path when completed */
    val localPath: String? = null,
    /** Error message if state is ERROR */
    val error: String? = null,
)

// MARK: - LoRA Download API

/**
 * Download a LoRA adapter from a URL to local storage.
 *
 * The adapter is saved to the lora directory under the SDK models path.
 * After download, use [loadLoraAdapter] to apply it.
 *
 * @param url Direct download URL for the .gguf LoRA file
 * @param filename Filename to save as (e.g., "my-lora.gguf")
 * @return Flow of download progress updates
 */
expect fun RunAnywhere.downloadLoraAdapter(url: String, filename: String): Flow<LoraDownloadProgress>

/**
 * Get the list of available hardcoded LoRA adapters for quick testing.
 *
 * @return List of catalog entries
 */
fun RunAnywhere.availableLoraAdapters(): List<LoraAdapterEntry> {
    return LoraAdapterCatalog.adapters
}

/**
 * Download a LoRA adapter from the built-in catalog.
 *
 * Convenience wrapper around [downloadLoraAdapter] using a catalog entry.
 *
 * @param entry Catalog entry to download
 * @return Flow of download progress updates
 */
fun RunAnywhere.downloadLoraFromCatalog(entry: LoraAdapterEntry): Flow<LoraDownloadProgress> {
    return downloadLoraAdapter(url = entry.url, filename = entry.filename)
}
