/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the model-assignment filter accessors.
 * Wave 2 KOTLIN: filters cached registry by framework/category.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

actual suspend fun RunAnywhere.getModelsForFramework(framework: InferenceFramework): List<ModelInfo> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return availableModels().filter { it.framework == framework }
}

actual suspend fun RunAnywhere.getModelsForCategory(category: ModelCategory): List<ModelInfo> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return availableModels().filter { it.category == category }
}
