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
import kotlinx.serialization.Serializable

// MARK: - LoRA Compatibility

@Serializable
data class LoraCompatibilityResult(
    val isCompatible: Boolean,
    val error: String? = null,
)

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

/**
 * Check if a LoRA adapter file is compatible with the currently loaded model.
 *
 * Reads GGUF metadata from the LoRA file and compares architecture
 * with the loaded model. Does not load the adapter.
 *
 * @param loraPath Path to the LoRA adapter GGUF file
 * @return Compatibility result with isCompatible flag and optional error
 */
expect fun RunAnywhere.checkLoraCompatibility(loraPath: String): LoraCompatibilityResult
