/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for proto-backed model and component
 * lifecycle operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private fun requireLifecycleInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

// MARK: - Lifecycle Operations

actual suspend fun RunAnywhere.loadModel(request: ModelLoadRequest): ModelLoadResult {
    requireLifecycleInitialized(this)
    return withContext(Dispatchers.IO) {
        CppBridgeModelLifecycleProto.load(request)
            ?: throw SDKException.model("Native model lifecycle load proto API unavailable")
    }
}

actual suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult {
    requireLifecycleInitialized(this)
    return CppBridgeModelLifecycleProto.unload(request)
        ?: throw SDKException.model("Native model lifecycle unload proto API unavailable")
}

actual suspend fun RunAnywhere.currentModel(request: CurrentModelRequest): CurrentModelResult {
    requireLifecycleInitialized(this)
    return CppBridgeModelLifecycleProto.currentModel(request)
        ?: throw SDKException.model("Native current model proto API unavailable")
}

actual suspend fun RunAnywhere.componentLifecycleSnapshot(
    component: SDKComponent,
): ComponentLifecycleSnapshot {
    requireLifecycleInitialized(this)
    return CppBridgeModelLifecycleProto.snapshot(component)
        ?: throw SDKException.model("Native component lifecycle snapshot proto API unavailable")
}

// MARK: - Model Loading

actual suspend fun RunAnywhere.loadModel(modelId: String) {
    requireLifecycleInitialized(this)
    val result = loadModel(ModelLoadRequest(model_id = modelId))
    if (!result.success) {
        throw SDKException.model(
            result.error_message.ifBlank { "Failed to load model '$modelId'" },
        )
    }
}

actual suspend fun RunAnywhere.loadLLMModel(modelId: String) {
    requireLifecycleInitialized(this)
    val framework =
        CppBridgeModelRegistry.get(modelId)?.framework
            ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                framework = framework,
            ),
        )
    if (!result.success) {
        throw SDKException.llm(result.error_message.ifBlank { "Failed to load LLM model '$modelId'" })
    }
}

actual suspend fun RunAnywhere.unloadLLMModel() {
    requireLifecycleInitialized(this)
    unloadModel(ModelUnloadRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE))
}

actual val RunAnywhere.isLLMModelLoaded: Boolean
    get() =
        CppBridgeModelLifecycleProto
            .snapshot(SDKComponent.SDK_COMPONENT_LLM)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            } ?: false

actual val RunAnywhere.currentLLMModel: ModelInfo?
    get() {
        val current =
            CppBridgeModelLifecycleProto.currentModel(
                CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE),
            ) ?: return null
        current.model?.let { return it }
        val modelId = current.model_id.takeIf { it.isNotEmpty() } ?: return null
        return CppBridgeModelRegistry.get(modelId)
    }

actual suspend fun RunAnywhere.currentSTTModel(): ModelInfo? {
    val current =
        currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION))
    current.model?.let { return it }
    val modelId = current.model_id.takeIf { it.isNotEmpty() } ?: return null
    return CppBridgeModelRegistry.get(modelId)
}

actual suspend fun RunAnywhere.loadSTTModel(modelId: String) {
    requireLifecycleInitialized(this)
    val framework =
        CppBridgeModelRegistry.get(modelId)?.framework
            ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                framework = framework,
            ),
        )
    if (!result.success) {
        throw SDKException.stt(result.error_message.ifBlank { "Failed to load STT model '$modelId'" })
    }
}
