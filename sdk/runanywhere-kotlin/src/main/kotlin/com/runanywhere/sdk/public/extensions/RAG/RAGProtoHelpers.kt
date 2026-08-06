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

import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import com.runanywhere.sdk.public.types.RAModelLoadResult
import com.runanywhere.sdk.public.types.RARAGConfiguration
import com.runanywhere.sdk.public.types.RARAGStatistics

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

// MARK: - RAGQueryOptions

/**
 * A [RAGQueryOptions] with only [question] filled in.
 *
 * `RAGQueryOptions` carries no `rac_default`-annotated fields at the message
 * level (idl/rag.proto): `question`/`retrieval_top_k`/`similarity_threshold`
 * are deleted outright, replaced by `query` + the nested optional
 * `RAGRetrievalOptions`, so there is no generated `defaults()` base to
 * layer onto -- the all-fields-unset constructor already is the default.
 */
fun RAGQueryOptions.Companion.defaults(question: String): RAGQueryOptions =
    RAGQueryOptions(query = question)

// MARK: - RAGResult

/**
 * Total query wall-clock time in seconds, derived by summing the retrieval
 * and generation phases: `total_time_ms` is deleted outright (idl/rag.proto)
 * with no replacement field, since it was always derivable from the two
 * phase timings this type still carries.
 */
val RAGResult.totalTime: Double
    get() = (retrieval_time_ms + generation_time_ms).toDouble() / 1000.0

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
