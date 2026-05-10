/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.EmbeddingsRequest
import ai.runanywhere.proto.v1.EmbeddingsResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter
import java.util.concurrent.ConcurrentHashMap

object CppBridgeEmbeddings {
    private val handles = ConcurrentHashMap<String, Long>()

    fun embed(request: EmbeddingsRequest, modelId: String): EmbeddingsResult {
        val handle =
            handles.computeIfAbsent(modelId) {
                RunAnywhereBridge.racEmbeddingsCreate(it).also { created ->
                    if (created == 0L) throw SDKException.operation("racEmbeddingsCreate returned 0")
                }
            }
        return decodeOrThrow(
            EmbeddingsResult.ADAPTER,
            RunAnywhereBridge.racEmbeddingsEmbedBatchProto(
                handle,
                EmbeddingsRequest.ADAPTER.encode(request),
            ),
            "racEmbeddingsEmbedBatchProto",
        )
    }

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
