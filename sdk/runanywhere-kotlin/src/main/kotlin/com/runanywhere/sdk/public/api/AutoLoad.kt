/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Internal auto-load path shared by every generation verb: name a model in the
 * options and the SDK resolves, downloads, and loads it before inference.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger

private val autoLoadLogger = SDKLogger("AutoLoad")

/**
 * Make [modelId] resident under [category], downloading it first when its bytes
 * are absent. Returns immediately when the model is already loaded.
 */
internal suspend fun ensureModelLoaded(
    modelId: String,
    category: ModelCategory,
    framework: InferenceFramework? = null,
    downloadIfNeeded: Boolean = true,
) {
    if (modelId.isBlank()) return

    val current = legacyCurrentModel(CurrentModelRequest(category = category))
    if (current.found && current.model_id == modelId) return

    val lookup = legacyGetModel(ModelGetRequest(model_id = modelId))
    val registered = lookup.model
    if (lookup.found && registered != null && registered.local_path.isEmpty() && downloadIfNeeded) {
        autoLoadLogger.info("Auto-downloading '$modelId' before load")
        legacyDownloadModel(registered)
    }

    val result =
        legacyLoadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = category,
                framework = framework ?: registered?.framework?.takeIf { it.value != 0 },
                validate_availability = true,
            ),
        )
    if (result.error != null) {
        throw SDKException.modelLoadFailed(
            modelId,
            result.error!!.message.ifBlank { "Model load failed" },
        )
    }
}

/**
 * Resolve the model id a generation should report, preferring the caller's pin
 * and falling back to whatever is resident under [category].
 */
internal suspend fun resolveActiveModelId(modelId: String?, category: ModelCategory): String {
    modelId?.takeIf { it.isNotBlank() }?.let { return it }
    val current = legacyCurrentModel(CurrentModelRequest(category = category))
    return if (current.found) current.model_id else ""
}

/** Auto-load whatever [options] names, then report the active model id. */
internal suspend fun prepareGeneration(
    options: LlmOptions,
    category: ModelCategory,
): String {
    options.model?.takeIf { it.isNotBlank() }?.let { ensureModelLoaded(it, category) }
    val active = resolveActiveModelId(options.model, category)
    if (active.isEmpty()) {
        throw SDKException.modelNotLoaded()
    }
    return active
}
