/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Embeddings proto types.
 *
 * Mirrors Swift `EmbeddingsProto+Helpers.swift`. Pure Kotlin math —
 * no JNI or platform dependencies.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingVector
import ai.runanywhere.proto.v1.EmbeddingsConfiguration
import ai.runanywhere.proto.v1.EmbeddingsOptions
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlin.math.sqrt

// MARK: - EmbeddingsConfiguration

/**
 * Default embeddings component configuration mirroring Swift
 * `RAEmbeddingsConfiguration.defaults(...)`.
 */
fun EmbeddingsConfiguration.Companion.defaults(
    modelId: String,
    embeddingDimension: Int = 384,
    maxSequenceLength: Int = 512,
    normalize: Boolean = true,
): EmbeddingsConfiguration =
    EmbeddingsConfiguration(
        model_id = modelId,
        embedding_dimension = embeddingDimension,
        max_sequence_length = maxSequenceLength,
        normalize = normalize,
    )

/**
 * Validate the embeddings component configuration. Throws an
 * [SDKException] mirroring Swift's `validate()` failures.
 */
fun EmbeddingsConfiguration.validate() {
    if (model_id.isEmpty()) {
        throw SDKException.invalidArgument("Embeddings modelID is empty")
    }
    if (embedding_dimension <= 0) {
        throw SDKException.invalidArgument(
            "Embedding dimension must be > 0 (got $embedding_dimension)",
        )
    }
    if (max_sequence_length <= 0) {
        throw SDKException.invalidArgument(
            "Max sequence length must be > 0 (got $max_sequence_length)",
        )
    }
}

// MARK: - EmbeddingsOptions

/**
 * Default per-call embeddings options mirroring Swift
 * `RAEmbeddingsOptions.defaults(normalize:)`.
 */
fun EmbeddingsOptions.Companion.defaults(normalize: Boolean = true): EmbeddingsOptions =
    EmbeddingsOptions(
        normalize = normalize,
    )

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

private fun l2(values: List<Float>): Float {
    var sumSquares = 0f
    for (v in values) {
        sumSquares += v * v
    }
    return sqrt(sumSquares)
}
