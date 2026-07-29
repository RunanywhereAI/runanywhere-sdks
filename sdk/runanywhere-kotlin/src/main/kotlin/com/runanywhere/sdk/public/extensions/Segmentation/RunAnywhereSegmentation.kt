/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSegmentation
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASegmentationRequest
import com.runanywhere.sdk.public.types.RASegmentationResult

/**
 * Segment one packed RGB8, RGBA8, or BGRA8 image with the currently loaded
 * semantic-segmentation model.
 *
 * The model must already have been imported or registered and loaded under
 * [ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION]. This call does not
 * download weights or create a second model owner; commons resolves the
 * lifecycle-owned service and returns source-dimension masks.
 */
suspend fun RunAnywhere.segment(request: RASegmentationRequest): RASegmentationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK")
    }
    ensureServicesReady()
    requireSegmentationModelLoaded(
        loadedModelSnapshot(ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION),
    )
    return CppBridgeSegmentation.segment(request)
}

internal fun requireSegmentationModelLoaded(snapshot: CurrentModelResult) {
    if (!snapshot.found) {
        throw SDKException.modelNotLoaded()
    }
}
