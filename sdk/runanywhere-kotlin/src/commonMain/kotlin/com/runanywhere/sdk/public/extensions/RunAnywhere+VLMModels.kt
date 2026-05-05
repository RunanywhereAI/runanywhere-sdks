/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VLM model loading helpers — Kotlin equivalent of Swift's RunAnywhere+VLMModels.swift.
 * Model file resolution is handled by C++ commons lifecycle artifacts.
 *
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Load a VLM model from a [ModelInfo] using the C++ model registry.
 *
 * The C++ lifecycle resolves primary and vision-projector artifacts and
 * returns them as generated `ModelFileDescriptor` values.
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
