/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for framework discovery + queries.
 * Backed by CppBridgeModelRegistry (the canonical model store).
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory

private fun bridgeFrameworkToPublic(value: Int): InferenceFramework =
    when (value) {
        CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.ONNX
        CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.LLAMA_CPP
        CppBridgeModelRegistry.Framework.SHERPA -> InferenceFramework.SHERPA
        CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.FOUNDATION_MODELS
        CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.SYSTEM_TTS
        CppBridgeModelRegistry.Framework.FLUID_AUDIO -> InferenceFramework.FLUID_AUDIO
        CppBridgeModelRegistry.Framework.BUILTIN -> InferenceFramework.BUILT_IN
        CppBridgeModelRegistry.Framework.NONE -> InferenceFramework.NONE
        CppBridgeModelRegistry.Framework.GENIE -> InferenceFramework.GENIE
        else -> InferenceFramework.UNKNOWN
    }

private fun bridgeCategoryToPublic(value: Int): ModelCategory =
    when (value) {
        CppBridgeModelRegistry.ModelCategory.LANGUAGE -> ModelCategory.LANGUAGE
        CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION -> ModelCategory.SPEECH_RECOGNITION
        CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS -> ModelCategory.SPEECH_SYNTHESIS
        CppBridgeModelRegistry.ModelCategory.AUDIO -> ModelCategory.AUDIO
        CppBridgeModelRegistry.ModelCategory.VISION -> ModelCategory.VISION
        CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION -> ModelCategory.IMAGE_GENERATION
        CppBridgeModelRegistry.ModelCategory.MULTIMODAL -> ModelCategory.MULTIMODAL
        CppBridgeModelRegistry.ModelCategory.EMBEDDING -> ModelCategory.EMBEDDING
        else -> ModelCategory.LANGUAGE
    }

actual suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    val all = CppBridgeModelRegistry.getAll()
    return all
        .map { bridgeFrameworkToPublic(it.framework) }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.getFrameworks(capability: SDKComponent): List<InferenceFramework> {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")

    val relevantCategories: Set<ModelCategory> =
        when (capability) {
            SDKComponent.LLM -> setOf(ModelCategory.LANGUAGE)
            SDKComponent.VLM -> setOf(ModelCategory.MULTIMODAL, ModelCategory.VISION)
            SDKComponent.STT -> setOf(ModelCategory.SPEECH_RECOGNITION)
            SDKComponent.TTS -> setOf(ModelCategory.SPEECH_SYNTHESIS)
            SDKComponent.VAD -> setOf(ModelCategory.AUDIO)
            SDKComponent.VOICE -> setOf(
                ModelCategory.LANGUAGE,
                ModelCategory.SPEECH_RECOGNITION,
                ModelCategory.SPEECH_SYNTHESIS,
            )
            SDKComponent.EMBEDDING -> setOf(ModelCategory.EMBEDDING)
            SDKComponent.RAG -> setOf(ModelCategory.LANGUAGE)
        }

    val all = CppBridgeModelRegistry.getAll()
    return all
        .filter { bridgeCategoryToPublic(it.category) in relevantCategories }
        .map { bridgeFrameworkToPublic(it.framework) }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.flushPendingRegistrations() {
    // Kotlin's registerModel is synchronous (CppBridgeModelRegistry.save).
    // Nothing to flush; this exists for cross-platform parity.
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
}

actual suspend fun RunAnywhere.discoverDownloadedModels() {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    CppBridgeModelRegistry.scanAndRestoreDownloadedModels()
}
