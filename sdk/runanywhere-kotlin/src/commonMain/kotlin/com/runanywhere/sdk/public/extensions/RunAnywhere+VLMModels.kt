/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VLM model loading helpers — Kotlin equivalent of Swift's RunAnywhere+VLMModels.swift.
 * Model file resolution (main model + mmproj) is handled in C++ commons.
 *
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

/**
 * Load a VLM model from a [ModelInfo] using the C++ model registry.
 *
 * The C++ layer handles resolving the model folder, finding the main
 * .gguf and mmproj .gguf files automatically.
 *
 * @param model The model to load (must be registered in the global registry).
 */
expect suspend fun RunAnywhere.loadVLMModelInfo(model: ModelInfo)

/**
 * Load a VLM model by ID using the C++ model registry. Alias for the
 * existing [loadVLMModel] entry point — preserved here for parity with
 * Swift's `loadVLMModelById(_:)`.
 *
 * @param modelId Model identifier (must be registered in the global registry).
 */
expect suspend fun RunAnywhere.loadVLMModelById(modelId: String)
