/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for framework discovery + queries.
 * Backed by CppBridgeModelRegistry (the canonical model store).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.displayName

actual suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val all = CppBridgeModelRegistry.getAll()
    return all
        .map { it.framework }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.getFrameworksForCapability(capability: SDKComponent): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val relevantCategories: Set<ModelCategory> =
        when (capability) {
            SDKComponent.SDK_COMPONENT_LLM -> setOf(ModelCategory.MODEL_CATEGORY_LANGUAGE)
            SDKComponent.SDK_COMPONENT_VLM ->
                setOf(ModelCategory.MODEL_CATEGORY_MULTIMODAL, ModelCategory.MODEL_CATEGORY_VISION)
            SDKComponent.SDK_COMPONENT_STT -> setOf(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
            SDKComponent.SDK_COMPONENT_TTS -> setOf(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
            SDKComponent.SDK_COMPONENT_VAD -> setOf(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)
            SDKComponent.SDK_COMPONENT_VOICE_AGENT ->
                setOf(
                    ModelCategory.MODEL_CATEGORY_LANGUAGE,
                    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                )
            SDKComponent.SDK_COMPONENT_EMBEDDINGS -> setOf(ModelCategory.MODEL_CATEGORY_EMBEDDING)
            SDKComponent.SDK_COMPONENT_RAG -> setOf(ModelCategory.MODEL_CATEGORY_LANGUAGE)
            else -> emptySet()
        }

    val all = CppBridgeModelRegistry.getAll()
    return all
        .filter { it.category in relevantCategories }
        .map { it.framework }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.flushPendingRegistrations() {
    // Kotlin's registerModel is synchronous (CppBridgeModelRegistry.save).
    // Nothing to flush; this exists for cross-platform parity.
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
}

actual suspend fun RunAnywhere.discoverDownloadedModels() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    refreshModelRegistry(
        includeRemoteCatalog = false,
        rescanLocal = true,
        pruneOrphans = false,
    )
}
