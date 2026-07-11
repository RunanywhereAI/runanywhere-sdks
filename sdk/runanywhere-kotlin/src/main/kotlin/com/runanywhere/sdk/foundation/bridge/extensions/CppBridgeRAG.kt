/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RARAGConfiguration
import com.runanywhere.sdk.public.types.RARAGDocument
import com.runanywhere.sdk.public.types.RARAGStatistics
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

internal data class NativeRAGQueryRequest(
    val queryProto: ByteArray,
)

object CppBridgeRAG {
    @Volatile private var sessionHandle: Long = 0L

    @Synchronized
    fun create(config: RARAGConfiguration) {
        destroy()
        val outRc = intArrayOf(RunAnywhereBridge.RAC_SUCCESS)
        val handle =
            RunAnywhereBridge.racRagSessionCreateProtoWithError(
                RAGConfiguration.ADAPTER.encode(config),
                outRc,
            )
        if (handle == 0L) {
            throw createSessionException(outRc[0])
        }
        sessionHandle = handle
    }

    @Synchronized
    fun destroy() {
        if (sessionHandle != 0L) RunAnywhereBridge.racRagSessionDestroyProto(sessionHandle)
        sessionHandle = 0L
    }

    fun ingest(document: RARAGDocument): RARAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagIngestProto(
                requireSession(),
                RAGDocument.ADAPTER.encode(document),
            ),
            "racRagIngestProto",
        )

    /** Encode immutable request data before cancellable JNI admission. */
    internal fun prepareQuery(options: RAGQueryOptions): NativeRAGQueryRequest =
        NativeRAGQueryRequest(
            queryProto = RAGQueryOptions.ADAPTER.encode(options),
        )

    internal fun queryRequest(
        requestId: Long,
        request: NativeRAGQueryRequest,
    ): RAGResult =
        decodeOrThrow(
            RAGResult.ADAPTER,
            RunAnywhereBridge.racRagQueryRequestProto(
                requestId,
                // The coordinator owns the lifecycle gate before this method
                // is called. Capture only now so a queued query cannot retain
                // a session that create/destroy replaces ahead of admission.
                requireSession(),
                request.queryProto,
            ),
            "racRagQueryRequestProto",
        )

    /** Cancel only the matching request-scoped JNI query wrapper. */
    internal fun cancelQueryRequest(
        requestId: Long,
    ) {
        // A running query holds the same coordinator gate used by every RAG
        // lifecycle mutation, so the current handle is exactly its handle.
        val rc = RunAnywhereBridge.racRagCancelRequestProto(requestId, requireSession())
        if (rc != RunAnywhereBridge.RAC_SUCCESS && rc != RunAnywhereBridge.RAC_ERROR_CANCELLED) {
            throw SDKException.operation("racRagCancelRequestProto failed: $rc")
        }
    }

    fun clear(): RARAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagClearProto(requireSession()),
            "racRagClearProto",
        )

    fun stats(): RARAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagStatsProto(requireSession()),
            "racRagStatsProto",
        )

    private fun requireSession(): Long =
        sessionHandle.takeIf { it != 0L } ?: throw SDKException.notInitialized("RAG session not created")

    private fun createSessionException(rc: Int): SDKException {
        if (rc == RunAnywhereBridge.RAC_SUCCESS) {
            return SDKException.operation("racRagSessionCreateProto returned 0")
        }
        val magnitude = if (rc < 0) -rc else rc
        val code = ErrorCode.fromValue(magnitude) ?: ErrorCode.ERROR_CODE_UNKNOWN
        return SDKException.make(
            code = code,
            message = "RAG proto session create failed: $rc",
            category = categoryForRacResult(magnitude),
            cAbiCode = rc,
        )
    }

    private fun categoryForRacResult(magnitude: Int): ErrorCategory =
        when (magnitude) {
            in 110..129 -> ErrorCategory.ERROR_CATEGORY_MODEL
            in 150..179 -> ErrorCategory.ERROR_CATEGORY_NETWORK
            in 180..219, in 330..369 -> ErrorCategory.ERROR_CATEGORY_IO
            in 250..279 -> ErrorCategory.ERROR_CATEGORY_VALIDATION
            in 320..329 -> ErrorCategory.ERROR_CATEGORY_AUTH
            in 100..109 -> ErrorCategory.ERROR_CATEGORY_CONFIGURATION
            in 400..499, in 600..999 -> ErrorCategory.ERROR_CATEGORY_INTERNAL
            else -> ErrorCategory.ERROR_CATEGORY_COMPONENT
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
