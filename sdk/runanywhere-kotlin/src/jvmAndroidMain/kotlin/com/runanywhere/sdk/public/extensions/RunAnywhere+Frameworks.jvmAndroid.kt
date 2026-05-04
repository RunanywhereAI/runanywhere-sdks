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
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory

actual suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val all = CppBridgeModelRegistry.getAll()
    return all
        .map { InferenceFramework.fromProto(it.framework) }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.getFrameworksForCapability(capability: SDKComponent): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val relevantCategories: Set<ModelCategory> =
        when (capability) {
            SDKComponent.LLM -> setOf(ModelCategory.LANGUAGE)
            SDKComponent.VLM -> setOf(ModelCategory.MULTIMODAL, ModelCategory.VISION)
            SDKComponent.STT -> setOf(ModelCategory.SPEECH_RECOGNITION)
            SDKComponent.TTS -> setOf(ModelCategory.SPEECH_SYNTHESIS)
            SDKComponent.VAD -> setOf(ModelCategory.VOICE_ACTIVITY_DETECTION)
            SDKComponent.VOICE ->
                setOf(
                    ModelCategory.LANGUAGE,
                    ModelCategory.SPEECH_RECOGNITION,
                    ModelCategory.SPEECH_SYNTHESIS,
                    ModelCategory.VOICE_ACTIVITY_DETECTION,
                )
            SDKComponent.EMBEDDING -> setOf(ModelCategory.EMBEDDING)
            SDKComponent.RAG -> setOf(ModelCategory.LANGUAGE)
        }

    val all = CppBridgeModelRegistry.getAll()
    return all
        .filter { ModelCategory.fromProto(it.category) in relevantCategories }
        .map { InferenceFramework.fromProto(it.framework) }
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
    CppBridgeModelRegistry.scanAndRestoreDownloadedModels()
}
