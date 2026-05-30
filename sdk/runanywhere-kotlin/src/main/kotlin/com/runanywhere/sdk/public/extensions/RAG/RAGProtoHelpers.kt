/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical RAG proto types. Mirrors the Swift
 * counterpart at
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RAGProto+Helpers.swift`.
 *
 * These helpers operate on the Wire-generated proto types directly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.types.RAModelLoadResult
import com.runanywhere.sdk.public.types.RARAGConfiguration
import com.runanywhere.sdk.public.types.RARAGDocument
import com.runanywhere.sdk.public.types.RARAGStatistics
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

// MARK: - RAGConfiguration

/**
 * Build a [RAGConfiguration] populated with the canonical defaults used by
 * the Swift SDK: 384-dim embeddings, top-K of 5, similarity threshold 0.7,
 * 512-token chunks with 64 tokens of overlap.
 */
fun RAGConfiguration.Companion.defaults(
    embeddingModelId: String = "",
    llmModelId: String = "",
): RARAGConfiguration =
    RARAGConfiguration(
        embedding_model_id = embeddingModelId,
        llm_model_id = llmModelId,
        embedding_dimension = 384,
        top_k = 5,
        similarity_threshold = 0.7f,
        chunk_size = 512,
        chunk_overlap = 64,
    )

/**
 * Validate the configuration matches the Swift contract:
 *  - top_k > 0
 *  - similarity_threshold in 0.0..1.0
 *  - chunk_size > 0
 *  - chunk_overlap >= 0 && chunk_overlap < chunk_size
 *
 * @throws SDKException if any constraint is violated.
 */
fun RARAGConfiguration.validate() {
    // The proto fields are `optional`, so Wire exposes them as nullable; an
    // unset field resolves to its canonical default (mirrors the defaults
    // factory above and the commons-side stamping).
    val effectiveTopK = top_k ?: 5
    if (effectiveTopK <= 0) {
        throw SDKException.invalidArgument("topK must be > 0 (got $effectiveTopK)")
    }
    val effectiveThreshold = similarity_threshold ?: 0.7f
    if (effectiveThreshold < 0f || effectiveThreshold > 1.0f) {
        throw SDKException.invalidArgument(
            "Similarity threshold must be in 0..1.0 (got $effectiveThreshold)",
        )
    }
    val effectiveChunkSize = chunk_size ?: 512
    if (effectiveChunkSize <= 0) {
        throw SDKException.invalidArgument("Chunk size must be > 0")
    }
    val effectiveChunkOverlap = chunk_overlap ?: 64
    if (effectiveChunkOverlap < 0 || effectiveChunkOverlap >= effectiveChunkSize) {
        throw SDKException.invalidArgument(
            "Chunk overlap must be >= 0 and < chunkSize (got $effectiveChunkOverlap vs $effectiveChunkSize)",
        )
    }
}

/**
 * Commons owns model-id → path resolution. This helper simply stamps
 * the resolved model ids returned by the lifecycle onto the configuration
 * and defers actual path resolution to the native RAG session-create ABI.
 *
 * Callers still pass [ModelLoadResult] so the lifecycle has been invoked
 * (which guarantees the models are registered) before the native create
 * runs.
 */
fun RARAGConfiguration.resolvingLifecycleArtifacts(
    embedding: RAModelLoadResult,
    llm: RAModelLoadResult,
): RARAGConfiguration =
    copy(
        embedding_model_id = embedding.model_id,
        llm_model_id = llm.model_id,
    )

// MARK: - RAGDocument

/**
 * Build a [RAGDocument] from raw text plus an optional JSON-encoded metadata
 * blob. The JSON object is decoded into the typed `metadata` map (string →
 * string), matching the Swift `RARAGDocument(text:metadataJSON:)`
 * initializer.
 *
 * The `metadata_json` proto field was removed; this helper decodes the
 * caller's blob into the typed `metadata` map so the wire payload stays
 * canonical.
 */
fun RAGDocument.Companion.create(
    text: String,
    metadataJSON: String? = null,
): RARAGDocument =
    RARAGDocument(text = text, metadata = decodeMetadataJSON(metadataJSON))

/**
 * Acronym-preserving alias matching the Swift `metadataJSON` accessor on
 * `RARAGDocument`. The Wire-generated Kotlin proto exposes the typed
 * `metadata` map under a snake_case name; this read-only extension property
 * surfaces the equivalent JSON-encoded blob for parity with the Swift API
 * (where the original proto field name `metadata_json` is camel-cased to
 * `metadataJSON`).
 */
val RARAGDocument.metadataJSON: String?
    get() {
        if (metadata.isEmpty()) return null
        // Encode the typed map as a JSON object so callers expecting the
        // Swift-style `metadataJSON` blob can round-trip the value.
        return buildString {
            append('{')
            metadata.entries.forEachIndexed { index, (key, value) ->
                if (index > 0) append(',')
                append('"').append(escapeJsonString(key)).append("\":\"")
                append(escapeJsonString(value)).append('"')
            }
            append('}')
        }
    }

private fun decodeMetadataJSON(metadataJSON: String?): Map<String, String> {
    if (metadataJSON.isNullOrEmpty()) return emptyMap()
    return runCatching { Json.parseToJsonElement(metadataJSON) }
        .getOrNull()
        ?.let { it as? JsonObject }
        ?.entries
        ?.associate { (key, value) ->
            val str =
                when (value) {
                    is JsonPrimitive -> value.contentOrNull ?: value.toString()
                    else -> value.toString()
                }
            key to str
        }
        ?: emptyMap()
}

private fun escapeJsonString(value: String): String =
    buildString(value.length) {
        for (c in value) {
            when (c) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(c)
            }
        }
    }

// MARK: - RAGQueryOptions

/**
 * Build a [RAGQueryOptions] with the same defaults the Swift SDK ships:
 * max_tokens = 512, temperature = 0.7, top_p = 1.0, top_k = 0.
 */
fun RAGQueryOptions.Companion.defaults(question: String): RAGQueryOptions =
    RAGQueryOptions(
        question = question,
        max_tokens = 512,
        temperature = 0.7f,
        top_p = 1.0f,
        top_k = 0,
    )

// MARK: - RAGResult

/** Total query wall-clock time in seconds (derived from `total_time_ms`). */
val RAGResult.totalTime: Double
    get() = total_time_ms.toDouble() / 1000.0

/** Retrieval-phase wall-clock time in seconds (derived from `retrieval_time_ms`). */
val RAGResult.retrievalTime: Double
    get() = retrieval_time_ms.toDouble() / 1000.0

/** LLM generation wall-clock time in seconds (derived from `generation_time_ms`). */
val RAGResult.generationTime: Double
    get() = generation_time_ms.toDouble() / 1000.0

// MARK: - RAGStatistics

/**
 * Epoch-millisecond timestamp of the most recent ingestion, or null if no
 * ingestion has occurred yet. Kotlin doesn't have an automatic `Date` type
 * here — consumers can convert this to `kotlinx.datetime.Instant` or
 * `java.util.Date` themselves if needed.
 */
val RARAGStatistics.lastUpdated: Long?
    get() = last_updated_ms.takeIf { it > 0L }

// `mergingRAGConfig` and the JSONSerialization-backed embedding-config
// merger are deliberately omitted — commons now resolves vocabulary paths
// itself from the registered model descriptor, so the SDK no longer
// assembles `embedding_config_json` on its side.
