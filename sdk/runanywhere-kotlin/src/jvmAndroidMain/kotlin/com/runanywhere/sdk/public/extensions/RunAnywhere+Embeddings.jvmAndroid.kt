/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for embeddings (B10).
 *
 * STUB: this facade is wired end-to-end on the Kotlin side, but the
 * JNI thunks (`racEmbeddingsCreate` / `racEmbeddingsEmbed` /
 * `racEmbeddingsDestroy`) are not yet declared in RunAnywhereBridge
 * because the matching C++ JNI wrappers do not exist yet either.
 *
 * TODO(B10): once the C++ JNI side lands, swap the `NotImplementedError`
 * below for a real implementation analogous to RunAnywhere+RAG. Required
 * pieces:
 *   1. Add three externals to RunAnywhereBridge.kt:
 *        @JvmStatic external fun racEmbeddingsCreate(modelId: String): Long
 *        @JvmStatic external fun racEmbeddingsEmbed(
 *            handle: Long, text: String, optionsBytes: ByteArray?,
 *        ): ByteArray?          // serialized EmbeddingsResult, null on error
 *        @JvmStatic external fun racEmbeddingsDestroy(handle: Long)
 *   2. Implement them in `sdk/runanywhere-commons/src/backends/jni/` (or
 *      a new `runanywhere_commons_embeddings_jni.cpp`) by forwarding to
 *      `rac_embeddings_create` / `rac_embeddings_embed` /
 *      `rac_embeddings_destroy`, serializing the resulting
 *      `rac_embeddings_result_t` into the canonical `EmbeddingsResult`
 *      proto bytes via the proto adapters in
 *      `include/rac/foundation/rac_proto_adapters.h`.
 *   3. Replace the stub body with a `withContext(Dispatchers.IO)` block
 *      that caches the handle keyed on `modelId` (see the embeddings
 *      actor in RunAnywhere+Embeddings.swift for the Swift pattern).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

@Suppress("UNUSED_PARAMETER")
actual suspend fun RunAnywhere.embed(
    text: String,
    modelId: String,
    options: EmbeddingsOptions?,
): EmbeddingsResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    throw SDKException.operation(
        "TODO(B10): RunAnywhere.embed is not wired yet on Kotlin. " +
            "JNI thunks racEmbeddingsCreate / racEmbeddingsEmbed / racEmbeddingsDestroy " +
            "plus the matching C++ JNI wrappers still need to be added. See the file " +
            "header for the required pieces.",
    )
}
