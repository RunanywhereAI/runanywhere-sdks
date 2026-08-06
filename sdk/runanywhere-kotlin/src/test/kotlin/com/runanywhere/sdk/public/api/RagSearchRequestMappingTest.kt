/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * `RAGSearchRequest.question`/`.retrieval_top_k`/`.enable_multi_query` are
 * deleted outright (idl/rag.proto): the flat fields collapsed onto the
 * shared `RAGRetrievalOptions` message (`query` + nested `retrieval`),
 * matching `RAGQueryOptions`'s shape. `RAGSearchResult.similarity_score`/
 * `.rank` are likewise deleted -- `score` (fused dense + BM25 RRF, not a raw
 * cosine similarity) is the sole relevance field now, and rank is
 * positional (list order), not a separate field.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.RAGRetrievalOptions
import ai.runanywhere.proto.v1.RAGSearchRequest
import ai.runanywhere.proto.v1.RAGSearchResponse
import ai.runanywhere.proto.v1.RAGSearchResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRAG
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RagSearchRequestMappingTest {
    @Test
    fun prepareSearchEncodesRetrievalOnlyRequest() {
        val request =
            CppBridgeRAG.prepareSearch(
                RAGSearchRequest(
                    query = "where is rag",
                    retrieval = RAGRetrievalOptions(top_k = 3),
                ),
            )
        val decoded = RAGSearchRequest.ADAPTER.decode(request.requestProto)
        assertEquals("where is rag", decoded.query)
        assertEquals(3, decoded.retrieval?.top_k)
        assertEquals(false, decoded.retrieval?.enable_multi_query)
    }

    @Test
    fun searchResponseChunksMapToMatches() {
        val response =
            RAGSearchResponse(
                chunks =
                    listOf(
                        RAGSearchResult(
                            chunk_id = "c1",
                            text = "retrieval only",
                            score = 0.91f,
                            source_document = "doc-a",
                        ),
                    ),
                retrieval_time_ms = 12L,
                request_id = "req-1",
            )
        val matches = response.chunks.map { it.toMatch() }
        assertEquals(1, matches.size)
        assertEquals("retrieval only", matches[0].text)
        assertTrue(matches[0].score >= 0.9f)
    }
}
