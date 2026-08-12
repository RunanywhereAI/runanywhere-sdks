/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Embeddings proto types.
 *
 * defaults() / validate() live in generated/convenience/RAConvenience.kt,
 * emitted from the canonical IDL annotations. This file contains only
 * Kotlin-specific computed helpers. Norm / cosine similarity are owned by
 * commons (`rac_embeddings_norm` / `rac_embeddings_similarity`) via JNI.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingVector
import ai.runanywhere.proto.v1.EmbeddingsResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEmbeddings

// MARK: - EmbeddingVector math

/**
 * Cosine similarity between two embedding vectors via
 * `rac_embeddings_similarity`. Returns 0 when either vector is empty, when
 * the dimensions differ, or when either L2 norm is zero.
 *
 * `EmbeddingVector.norm` is deleted outright (idl/embeddings_options.proto)
 * with no replacement -- there is no cached norm to read. Mirrors Swift's
 * `RAEmbeddingVector.cosineSimilarity(with:)`.
 */
fun EmbeddingVector.cosineSimilarity(other: EmbeddingVector): Float =
    CppBridgeEmbeddings.similarity(
        values.toFloatArray(),
        other.values.toFloatArray(),
    )

/**
 * L2 norm of the vector via `rac_embeddings_norm`. Equivalent to Swift's
 * `computeNorm()`.
 */
fun EmbeddingVector.computeNorm(): Float =
    CppBridgeEmbeddings.norm(values.toFloatArray())

/** Embeddings processing time in seconds, matching Swift's TimeInterval helper. */
val EmbeddingsResult.processingTime: Double
    get() = processing_time_ms / 1_000.0
