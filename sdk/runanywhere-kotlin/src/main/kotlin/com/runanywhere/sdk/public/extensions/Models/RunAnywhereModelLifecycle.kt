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
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The C++ lifecycle service is the canonical source of truth for "is this
// modality loaded". Inference paths consult it via `acquire_lifecycle_*`, so
// there is nothing to mirror onto a Kotlin-side VLM bridge handle anymore.
// The last remnant of the VLM-specific synchroniser was removed on Swift;
// this Kotlin counterpart was removed in parity with that.

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
        try {
            ensureServicesReady()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
        val result =
            CppBridgeModelLifecycle.load(request)
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

suspend fun RunAnywhere.loadModel(model: RAModelInfo): RAModelLoadResult =
    loadModel(
        RAModelLoadRequest(
            model_id = model.id,
            category = model.lifecycleLoadCategory,
            framework = model.lifecycleLoadFramework,
        ),
    )

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

suspend fun RunAnywhere.currentModel(request: CurrentModelRequest = CurrentModelRequest()): CurrentModelResult =
    CppBridgeModelLifecycle.currentModel(request) ?: CurrentModelResult()

suspend fun RunAnywhere.currentModel(model: RAModelInfo): CurrentModelResult {
    for (category in model.lifecycleLookupCategories) {
        val result = currentModel(CurrentModelRequest(category = category))
        if (result.found) return result
    }
    return CurrentModelResult()
}

suspend fun RunAnywhere.currentModel(candidates: Iterable<RAModelInfo>): CurrentModelResult? {
    val candidateList = candidates.toList()
    val candidateIds = candidateList.mapTo(mutableSetOf()) { it.id }
    if (candidateIds.isEmpty()) return null

    val queriedCategories = mutableSetOf<ModelCategory>()
    for (model in candidateList) {
        for (category in model.lifecycleLookupCategories) {
            if (!queriedCategories.add(category)) continue
            val result = currentModel(CurrentModelRequest(category = category))
            if (result.found && result.model_id in candidateIds) return result
        }
    }
    return null
}

fun RAModelInfo.matchesLifecycleCategory(category: ModelCategory): Boolean =
    category in lifecycleLookupCategories

val RAModelInfo.isVisionLanguageModel: Boolean
    get() = matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_MULTIMODAL)

internal suspend fun RunAnywhere.loadedModelSnapshot(
    category: ModelCategory,
    includeModelMetadata: Boolean = false,
): CurrentModelResult =
    currentModel(
        CurrentModelRequest(
            category = category,
            include_model_metadata = includeModelMetadata,
        ),
    )

internal suspend fun RunAnywhere.firstLoadedModelSnapshot(
    categories: List<ModelCategory>,
    includeModelMetadata: Boolean = false,
): CurrentModelResult? {
    for (category in categories) {
        val result = loadedModelSnapshot(category = category, includeModelMetadata = includeModelMetadata)
        if (result.found) return result
    }
    return null
}

/**
 * Full [ModelInfo] for the model currently loaded under [category], or `null`
 * when nothing is loaded for it.
 *
 * Wraps [currentModel] with `includeModelMetadata = true` so callers (e.g. view
 * models surfacing the loaded model's display name / framework) get the
 * populated proto instead of reconstructing a stand-in.
 */
suspend fun RunAnywhere.modelInfoForCategory(category: ModelCategory): ModelInfo? {
    val result = loadedModelSnapshot(category = category, includeModelMetadata = true)
    return if (result.found) result.model else null
}

suspend fun RunAnywhere.componentLifecycleSnapshot(
    component: SDKComponent,
): ComponentLifecycleSnapshot? = CppBridgeModelLifecycle.snapshot(component)

private val RAModelInfo.lifecycleLoadCategory: ModelCategory?
    get() =
        category.takeUnless {
            it == ModelCategory.MODEL_CATEGORY_UNSPECIFIED
        }

private val RAModelInfo.lifecycleLoadFramework: InferenceFramework?
    get() =
        framework.takeUnless {
            it == InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED ||
                it == InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
        }

private val RAModelInfo.lifecycleLookupCategories: List<ModelCategory>
    get() =
        when (category) {
            ModelCategory.MODEL_CATEGORY_MULTIMODAL ->
                listOf(
                    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                    ModelCategory.MODEL_CATEGORY_VISION,
                )
            ModelCategory.MODEL_CATEGORY_VISION ->
                listOf(
                    ModelCategory.MODEL_CATEGORY_VISION,
                    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                )
            ModelCategory.MODEL_CATEGORY_UNSPECIFIED -> emptyList()
            else -> listOf(category)
        }
