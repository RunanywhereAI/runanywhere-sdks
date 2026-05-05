/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for VLM model loading helpers.
 * Wave 2 KOTLIN: Forwards to existing loadVLMModel(modelId) entry points.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere

actual suspend fun RunAnywhere.loadVLMModelInfo(model: ModelInfo) {
    loadVLMModel(model.id)
}

actual suspend fun RunAnywhere.loadVLMModelById(modelId: String) {
    loadVLMModel(modelId)
}
