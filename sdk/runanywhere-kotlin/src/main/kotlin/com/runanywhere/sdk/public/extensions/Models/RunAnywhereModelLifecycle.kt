/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for proto-backed model and component lifecycle.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+ModelLifecycle.swift.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The C++ lifecycle service is the canonical source of truth for "is this
// modality loaded". Inference paths consult it via `acquire_lifecycle_*`, so
// there is nothing to mirror onto a Kotlin-side VLM bridge handle anymore.
// Wave 7 / T23 removed the last remnant of the VLM-specific synchroniser on
// Swift; this Kotlin counterpart was removed in parity with that wave.

private val logger = SDKLogger("ModelLifecycle")

suspend fun RunAnywhere.loadModel(request: RAModelLoadRequest): RAModelLoadResult =
    withContext(Dispatchers.IO) {
        if (!isInitialized) {
            return@withContext RAModelLoadResult(
                success = false,
                model_id = request.model_id,
                category = request.category ?: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
                framework = request.framework ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED,
                error_message = "SDK not initialized",
            )
        }
        try { ensureServicesReady() } catch (_: Throwable) {}
        val result = CppBridgeModelLifecycle.load(request)
            ?: return@withContext RAModelLoadResult(
                success = false,
                model_id = request.model_id,
                category = request.category ?: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
                framework = request.framework ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED,
                error_message = "Native model lifecycle load proto API unavailable",
            )
        if (result.success) {
            val modelID = result.model_id.ifEmpty { request.model_id }
            logger.info("Model load succeeded for $modelID")
        }
        result
    }

suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult {
    if (!isInitialized) {
        return ModelUnloadResult(
            success = false,
            error_message = "SDK not initialized",
        )
    }
    return CppBridgeModelLifecycle.unload(request)
        ?: ModelUnloadResult(
            success = false,
            error_message = "Native model lifecycle unload proto API unavailable",
        )
}

suspend fun RunAnywhere.currentModel(request: CurrentModelRequest): CurrentModelResult =
    CppBridgeModelLifecycle.currentModel(request) ?: CurrentModelResult()

/**
 * Full [ModelInfo] for the model currently loaded under [category], or `null`
 * when nothing is loaded for it.
 *
 * Wraps [currentModel] with `includeModelMetadata = true` so callers (e.g. view
 * models surfacing the loaded model's display name / framework) get the
 * populated proto instead of reconstructing a stand-in.
 */
suspend fun RunAnywhere.modelInfoForCategory(category: ModelCategory): ModelInfo? {
    val result = currentModel(
        CurrentModelRequest(category = category, include_model_metadata = true),
    )
    return if (result.found) result.model else null
}

suspend fun RunAnywhere.componentLifecycleSnapshot(
    component: SDKComponent,
): ComponentLifecycleSnapshot? = CppBridgeModelLifecycle.snapshot(component)
