/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.embeddings` and `RunAnywhere.rerank`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.EmbeddingsRequest
import ai.runanywhere.proto.v1.RerankRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEmbeddings
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Text embeddings from the loaded embedding model.
 *
 * ```kotlin
 * val vectors = RunAnywhere.embeddings.embed(listOf("hello", "goodbye"))
 * println(vectors.first().vector.size)
 * ```
 */
public class EmbeddingsNamespace internal constructor() {
    /**
     * Embed [texts], returning one vector per input in input order.
     *
     * @throws SDKException when no embedding model is loaded.
     */
    public suspend fun embed(texts: List<String>, options: EmbedOptions? = null): List<Embedding> {
        if (texts.isEmpty()) return emptyList()
        RunAnywhere.ensureServicesReady()
        val modelId = resolveActiveModelId(null, ModelCategory.MODEL_CATEGORY_EMBEDDING)
        if (modelId.isEmpty()) throw SDKException.modelNotLoaded()
        return CppBridgeEmbeddings
            .embedBatchLifecycle(
                EmbeddingsRequest(
                    texts = texts,
                    options = options.orDefault().toProto(),
                    model_id = modelId,
                ),
            ).toEmbeddings()
    }
}

/**
 * Cross-encoder reranking with the loaded rerank model.
 *
 * ```kotlin
 * val ranked = RunAnywhere.rerank.rerank("battery life", passages, topN = 3)
 * println(passages[ranked.first().index])
 * ```
 */
public class RerankNamespace internal constructor() {
    /**
     * Score [documents] against [query] and return index pointers, best first.
     *
     * @throws SDKException when no rerank model is loaded.
     */
    public suspend fun rerank(
        query: String,
        documents: List<String>,
        topN: Int? = null,
    ): List<RankedResult> {
        if (documents.isEmpty()) return emptyList()
        // `RerankCandidate` is deleted outright (idl/rerank.proto): every
        // facade already built it with `id` set to the stringified array
        // index, so the wrapper carried no information the flat `documents`
        // list does not. `RerankRequest.documents` is now a plain
        // `repeated string`, and `RerankScoredItem.index` points back into it.
        return legacyRerank(
            RerankRequest(
                query = query,
                documents = documents,
                options = rerankOptions(topN),
            ),
        ).toRankedResults()
    }
}
