/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

object CppBridgeRAG {
    @Volatile private var sessionHandle: Long = 0L

    @Synchronized
    fun create(config: RAGConfiguration) {
        destroy()
        val handle =
            RunAnywhereBridge.racRagSessionCreateProto(RAGConfiguration.ADAPTER.encode(config))
        if (handle == 0L) {
            throw SDKException.operation("racRagSessionCreateProto returned 0")
        }
        sessionHandle = handle
    }

    @Synchronized
    fun destroy() {
        if (sessionHandle != 0L) RunAnywhereBridge.racRagSessionDestroyProto(sessionHandle)
        sessionHandle = 0L
    }

    fun ingest(document: RAGDocument): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagIngestProto(
                requireSession(),
                RAGDocument.ADAPTER.encode(document),
            ),
            "racRagIngestProto",
        )

    fun query(options: RAGQueryOptions): RAGResult =
        decodeOrThrow(
            RAGResult.ADAPTER,
            RunAnywhereBridge.racRagQueryProto(
                requireSession(),
                RAGQueryOptions.ADAPTER.encode(options),
            ),
            "racRagQueryProto",
        )

    fun clear(): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagClearProto(requireSession()),
            "racRagClearProto",
        )

    fun stats(): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagStatsProto(requireSession()),
            "racRagStatsProto",
        )

    private fun requireSession(): Long =
        sessionHandle.takeIf { it != 0L } ?: throw SDKException.notInitialized("RAG session not created")

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
