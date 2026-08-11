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
import com.runanywhere.sdk.public.types.RARerankOptions
import com.runanywhere.sdk.public.types.RARerankRequest
import com.runanywhere.sdk.public.types.RARerankResult

/**
 * Score every candidate against [query] with the currently-loaded cross-encoder
 * rerank model and return them ordered by descending relevance.
 *
 * `RerankCandidate` is deleted outright (idl/rerank.proto): every facade
 * already built it with `id` set to the stringified array index, so the
 * wrapper carried no information the flat `documents` list below does not.
 * `RerankRequest.documents` is now a plain `repeated string`, and
 * `RerankScoredItem.index` points back into it. Mirrors Swift's
 * `RunAnywhere.rerank(query:documents:options:)` convenience.
 */
@Deprecated("Use RunAnywhere.rerank.rerank(query, documents, topN).")
suspend fun RunAnywhere.rerank(
    query: String,
    documents: List<String>,
    options: RARerankOptions = RARerankOptions(),
): RARerankResult =
    rerank(
        RerankRequest(
            query = query,
            documents = documents,
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
@Deprecated("Use RunAnywhere.rerank.rerank(query, documents, topN).")
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
