/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Embeddings proto bridge. Mirrors Swift
 * `CppBridge.EmbeddingsProto.embedBatchLifecycle`: dispatches through the
 * lifecycle-aware ABI `rac_embeddings_embed_batch_lifecycle_proto` so embed
 * calls resolve the model loaded via `RunAnywhere.loadModel(category=EMBEDDING)`
 * instead of spinning up a parallel per-handle engine.
 *
 * Vector math (`norm` / `similarity`) is a thin JNI pass-through to
 * `rac_embeddings_norm` / `rac_embeddings_similarity`.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.EmbeddingsRequest
import ai.runanywhere.proto.v1.EmbeddingsResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAEmbeddingsResult
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

object CppBridgeEmbeddings {
    /**
     * Generate embeddings using the model loaded in the commons embeddings
     * lifecycle. The caller is expected to have already loaded an embeddings
     * model (e.g. via `RunAnywhere.loadModel` with `category = EMBEDDING`);
     * commons resolves the active lifecycle component internally — no handle
     * threading.
     */
    fun embedBatchLifecycle(request: EmbeddingsRequest): RAEmbeddingsResult =
        decodeOrThrow(
            EmbeddingsResult.ADAPTER,
            RunAnywhereBridge.racEmbeddingsEmbedBatchLifecycleProto(
                EmbeddingsRequest.ADAPTER.encode(request),
            ),
            "racEmbeddingsEmbedBatchLifecycleProto",
        )

    /** L2 norm via `rac_embeddings_norm`. */
    fun norm(vector: FloatArray): Float = RunAnywhereBridge.racEmbeddingsNorm(vector)

    /** Cosine similarity via `rac_embeddings_similarity`. */
    fun similarity(lhs: FloatArray, rhs: FloatArray): Float =
        RunAnywhereBridge.racEmbeddingsSimilarity(lhs, rhs)

    private fun <M : Message<M, *>> decodeOrThrow(
        adapter: ProtoAdapter<M>,
        bytes: ByteArray?,
        operation: String,
    ): M {
        val payload = bytes ?: throw SDKException.operation("$operation returned null")
        return try {
            adapter.decode(payload)
        } catch (e: Exception) {
            throw SDKException.operation("Failed to decode $operation result: ${e.message}")
        }
    }
}
