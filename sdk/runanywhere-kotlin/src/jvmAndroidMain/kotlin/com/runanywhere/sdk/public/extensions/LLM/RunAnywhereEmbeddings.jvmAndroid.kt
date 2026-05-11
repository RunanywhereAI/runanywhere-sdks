/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for embeddings (B10).
 *
 * JVM/Android actual for embeddings (B10), backed by the generated-proto
 * embeddings service ABI.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEmbeddings
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAEmbeddingsResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual suspend fun RunAnywhere.embed(
    text: String,
    modelId: String,
    options: EmbeddingsOptions?,
): RAEmbeddingsResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return withContext(Dispatchers.IO) {
        CppBridgeEmbeddings.embed(
            EmbeddingsRequest(texts = listOf(text), options = options),
            modelId,
        )
    }
}
