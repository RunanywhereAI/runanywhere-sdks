/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Embeddings proto types.
 *
 * defaults() / validate() live in generated/convenience/RAConvenience.kt,
 * emitted from the canonical IDL annotations. This file contains only
 * Kotlin-specific computed helpers.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingVector
import ai.runanywhere.proto.v1.EmbeddingsResult
import kotlin.math.sqrt

// MARK: - EmbeddingVector math

/**
 * Cosine similarity between two embedding vectors. Returns 0 when either
 * vector is empty, when the dimensions differ, or when either L2 norm
 * is zero. When the proto carries a precomputed `norm`, that value is
 * used in place of recomputing — matching Swift's `hasNorm` behavior.
 */
fun EmbeddingVector.cosineSimilarity(other: EmbeddingVector): Float {
    if (values.size != other.values.size || values.isEmpty()) return 0f
    var dot = 0f
    for (i in values.indices) {
        dot += values[i] * other.values[i]
    }
    val aNorm = norm ?: l2(values)
    val bNorm = other.norm ?: l2(other.values)
    if (aNorm <= 0f || bNorm <= 0f) return 0f
    return dot / (aNorm * bNorm)
}

/**
 * L2 norm of the vector. Equivalent to Swift's `computeNorm()`.
 */
fun EmbeddingVector.computeNorm(): Float = l2(values)

/** Embeddings processing time in seconds, matching Swift's TimeInterval helper. */
val EmbeddingsResult.processingTime: Double
    get() = processing_time_ms / 1_000.0

private fun l2(values: List<Float>): Float {
    var sumSquares = 0f
    for (v in values) {
        sumSquares += v * v
    }
    return sqrt(sumSquares)
}
