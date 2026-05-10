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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.resolvedPrimaryModelPath
import com.runanywhere.sdk.public.extensions.Models.resolvedVisionProjectorPath
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private fun requireLifecycleInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

private fun ModelCategory.isVLMCategory(): Boolean =
    this == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
        this == ModelCategory.MODEL_CATEGORY_VISION

// MARK: - Lifecycle Operations

actual suspend fun RunAnywhere.loadModel(request: ModelLoadRequest): ModelLoadResult {
    requireLifecycleInitialized(this)
    val result =
        withContext(Dispatchers.IO) {
            CppBridgeModelLifecycle.load(request)
                ?: throw SDKException.model("Native model lifecycle load proto API unavailable")
        }
    if (!result.success) {
        return result
    }
    // VLM still needs Kotlin-side bridge sync because its process/stream API
    // reads from CppBridgeVLM's handle, which is distinct from the
    // lifecycle's internal handle. Mirrors Swift synchronizeVLMComponentLoad.
    if (result.category.isVLMCategory()) {
        return synchronizeVLMComponentLoad(result)
    }
    return result
}

actual suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult {
    requireLifecycleInitialized(this)
    val loadedVLMModelId = currentVLMComponentModelId()
    val result =
        CppBridgeModelLifecycle.unload(request)
            ?: throw SDKException.model("Native model lifecycle unload proto API unavailable")
    if (shouldUnloadVLMComponent(request, result, loadedVLMModelId)) {
        CppBridgeVLM.destroy()
    }
    return result
}

/**
 * Sync the Kotlin VLM bridge to the just-loaded lifecycle artifacts so that
 * `processImage` / `processImageStream` resolve through the same handle.
 *
 * Mirrors Swift `synchronizeVLMComponentLoad`. On failure, this rolls back
 * the lifecycle load and surfaces the error message via the result.
 */
private suspend fun synchronizeVLMComponentLoad(result: ModelLoadResult): ModelLoadResult {
    val primaryPath = result.resolvedPrimaryModelPath()
    val projectorPath = result.resolvedVisionProjectorPath()
    if (primaryPath == null || projectorPath == null) {
        rollbackVLMLifecycle(result)
        return result.copy(
            success = false,
            error_message =
                result.error_message.ifBlank {
                    "VLM lifecycle did not resolve VLM artifacts for '${result.model_id}'"
                },
        )
    }
    val rc =
        try {
            CppBridgeVLM.loadResolvedArtifacts(
                modelId = result.model_id,
                primaryModelPath = primaryPath,
                visionProjectorPath = projectorPath,
            )
        } catch (e: Throwable) {
            rollbackVLMLifecycle(result)
            return result.copy(
                success = false,
                error_message = e.message ?: "VLM bridge sync failed",
            )
        }
    if (rc != 0) {
        rollbackVLMLifecycle(result)
        return result.copy(
            success = false,
            error_message = "VLM bridge sync failed (rc=$rc)",
        )
    }
    return result
}

/**
 * Decide whether the Kotlin VLM bridge should also be torn down after a
 * lifecycle unload. Mirrors Swift `shouldUnloadVLMComponent`.
 */
private fun shouldUnloadVLMComponent(
    request: ModelUnloadRequest,
    result: ModelUnloadResult,
    loadedModelId: String?,
): Boolean {
    if (request.unload_all) {
        return true
    }
    if (request.category != null && request.category.isVLMCategory()) {
        return true
    }
    if (loadedModelId.isNullOrBlank()) {
        return false
    }
    return loadedModelId in result.unloaded_model_ids
}

private fun currentVLMComponentModelId(): String? {
    if (!CppBridgeVLM.isLoaded()) return null
    val categories =
        listOf(ModelCategory.MODEL_CATEGORY_MULTIMODAL, ModelCategory.MODEL_CATEGORY_VISION)
    return categories.firstNotNullOfOrNull { category ->
        CppBridgeModelLifecycle
            .currentModel(CurrentModelRequest(category = category))
            ?.takeIf { it.found }
            ?.model_id
            ?.takeIf { it.isNotBlank() }
    }
}

private fun rollbackVLMLifecycle(result: ModelLoadResult) {
    try {
        CppBridgeModelLifecycle.unload(
            ModelUnloadRequest(
                model_id = result.model_id,
                category = result.category,
            ),
        )
    } catch (_: Throwable) {
        // Best-effort rollback; the caller already sees the failure.
    }
    CppBridgeVLM.destroy()
}

actual suspend fun RunAnywhere.currentModel(request: CurrentModelRequest): CurrentModelResult {
    requireLifecycleInitialized(this)
    return CppBridgeModelLifecycle.currentModel(request)
        ?: throw SDKException.model("Native current model proto API unavailable")
}

actual suspend fun RunAnywhere.componentLifecycleSnapshot(
    component: SDKComponent,
): ComponentLifecycleSnapshot {
    requireLifecycleInitialized(this)
    return CppBridgeModelLifecycle.snapshot(component)
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
        CppBridgeModelLifecycle
            .snapshot(SDKComponent.SDK_COMPONENT_LLM)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            } ?: false

actual val RunAnywhere.currentLLMModel: ModelInfo?
    get() {
        val current =
            CppBridgeModelLifecycle.currentModel(
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
