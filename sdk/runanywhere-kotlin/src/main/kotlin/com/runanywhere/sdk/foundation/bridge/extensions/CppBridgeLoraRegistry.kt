/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAApplyRequest
import ai.runanywhere.proto.v1.LoRAApplyResult
import ai.runanywhere.proto.v1.LoRARemoveRequest
import ai.runanywhere.proto.v1.LoRAState
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import ai.runanywhere.proto.v1.LoraAdapterImportRequest
import ai.runanywhere.proto.v1.LoraAdapterImportResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RALoRAAdapterConfig
import com.runanywhere.sdk.public.types.RALoRAApplyRequest
import com.runanywhere.sdk.public.types.RALoRARemoveRequest
import com.runanywhere.sdk.public.types.RALoRAState
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

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

/**
 * Mirrors Swift `CppBridge+LoraRegistry.swift` (with catalog operations from
 * `CppBridge+ModalityProtoABI.swift`). Wraps `rac_lora_*_proto` C ABI.
 */
object CppBridgeLoraRegistry {
    suspend fun apply(request: RALoRAApplyRequest): LoRAApplyResult =
        decodeOrThrow(
            LoRAApplyResult.ADAPTER,
            RunAnywhereBridge.racLoraApplyProto(LoRAApplyRequest.ADAPTER.encode(request)),
            "racLoraApplyProto",
        )

    suspend fun remove(request: RALoRARemoveRequest): RALoRAState =
        decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraRemoveProto(LoRARemoveRequest.ADAPTER.encode(request)),
            "racLoraRemoveProto",
        )

    suspend fun list(request: RALoRAState): RALoRAState =
        decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraListProto(LoRAState.ADAPTER.encode(request)),
            "racLoraListProto",
        )

    suspend fun state(request: RALoRAState): RALoRAState =
        decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraStateProto(LoRAState.ADAPTER.encode(request)),
            "racLoraStateProto",
        )

    suspend fun compatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult =
        decodeOrThrow(
            LoraCompatibilityResult.ADAPTER,
            RunAnywhereBridge.racLoraCompatibilityProto(LoRAAdapterConfig.ADAPTER.encode(config)),
            "racLoraCompatibilityProto",
        )

    fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        decodeOrThrow(
            LoraAdapterCatalogEntry.ADAPTER,
            RunAnywhereBridge.racLoraRegisterProto(LoraAdapterCatalogEntry.ADAPTER.encode(entry)),
            "racLoraRegisterProto",
        )

    fun listCatalog(request: LoraAdapterCatalogListRequest): LoraAdapterCatalogListResult =
        decodeOrThrow(
            LoraAdapterCatalogListResult.ADAPTER,
            RunAnywhereBridge.racLoraCatalogListProto(
                LoraAdapterCatalogListRequest.ADAPTER.encode(request),
            ),
            "racLoraCatalogListProto",
        )

    fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        decodeOrThrow(
            LoraAdapterCatalogListResult.ADAPTER,
            RunAnywhereBridge.racLoraCatalogQueryProto(
                LoraAdapterCatalogQuery.ADAPTER.encode(query),
            ),
            "racLoraCatalogQueryProto",
        )

    fun getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult =
        decodeOrThrow(
            LoraAdapterCatalogGetResult.ADAPTER,
            RunAnywhereBridge.racLoraCatalogGetProto(
                LoraAdapterCatalogGetRequest.ADAPTER.encode(request),
            ),
            "racLoraCatalogGetProto",
        )

    fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        decodeOrThrow(
            LoraAdapterDownloadCompletedResult.ADAPTER,
            RunAnywhereBridge.racLoraCatalogMarkDownloadCompletedProto(
                LoraAdapterDownloadCompletedRequest.ADAPTER.encode(request),
            ),
            "racLoraCatalogMarkDownloadCompletedProto",
        )

    fun importAdapter(request: LoraAdapterImportRequest): LoraAdapterImportResult =
        decodeOrThrow(
            LoraAdapterImportResult.ADAPTER,
            RunAnywhereBridge.racLoraAdapterImportProto(
                LoraAdapterImportRequest.ADAPTER.encode(request),
            ),
            "racLoraAdapterImportProto",
        )
}
