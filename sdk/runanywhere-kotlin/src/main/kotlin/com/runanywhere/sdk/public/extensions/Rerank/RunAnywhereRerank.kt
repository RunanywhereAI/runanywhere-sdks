/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for cross-encoder reranking operations.
 * Calls C++ directly via CppBridgeRerank for all operations.
 *
 * Mirrors Swift RunAnywhere+Rerank.swift exactly (offline `rerank`).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.RerankRequest
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRerank
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RARerankCandidate
import com.runanywhere.sdk.public.types.RARerankOptions
import com.runanywhere.sdk.public.types.RARerankRequest
import com.runanywhere.sdk.public.types.RARerankResult

/**
 * Score every candidate against [query] with the currently-loaded cross-encoder
 * rerank model and return them ordered by descending relevance.
 *
 * Mirrors Swift's `RunAnywhere.rerank(query:candidates:options:)` convenience.
 */
suspend fun RunAnywhere.rerank(
    query: String,
    candidates: List<RARerankCandidate>,
    options: RARerankOptions = RARerankOptions(),
): RARerankResult =
    rerank(
        RerankRequest(
            query = query,
            candidates = candidates,
            options = options,
        ),
    )

/**
 * Canonical request-based cross-encoder reranking entry point.
 *
 * Mirrors Swift's `RunAnywhere.rerank(_ request:)`. The model must already have
 * been imported/registered and loaded under the rerank component
 * ([SDKComponent.SDK_COMPONENT_RERANK]); this call never downloads weights or
 * creates a second model owner.
 */
suspend fun RunAnywhere.rerank(request: RARerankRequest): RARerankResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK")
    }
    ensureServicesReady()
    val snapshot =
        componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_RERANK)
            ?: throw SDKException.modelNotLoaded()
    val loadedModelId = snapshot.model_id.ifEmpty { snapshot.model?.id.orEmpty() }
    if (loadedModelId.isEmpty()) {
        throw SDKException.modelNotLoaded()
    }
    return CppBridgeRerank.rerank(request, snapshot)
}
