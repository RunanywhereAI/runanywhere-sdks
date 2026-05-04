/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for the device-side model-assignment manager.
 * Mirrors Swift RunAnywhere+ModelAssignments.swift.
 *
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 *
 * Note: `fetchModelAssignments` already exists in RunAnywhere+ModelManagement.kt;
 * this file adds the per-framework / per-category filter accessors that
 * Swift exposes alongside it.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

/**
 * Filter cached model assignments by inference framework.
 *
 * @param framework The framework (LLAMA_CPP, ONNX, ...) to filter by.
 * @return Models compatible with the given framework.
 */
expect suspend fun RunAnywhere.getModelsForFramework(framework: InferenceFramework): List<ModelInfo>

/**
 * Filter cached model assignments by model category.
 *
 * @param category The category (LANGUAGE, SPEECH_RECOGNITION, ...) to filter by.
 * @return Models in the given category.
 */
expect suspend fun RunAnywhere.getModelsForCategory(category: ModelCategory): List<ModelInfo>
