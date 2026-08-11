/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraApplyResult
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
    suspend fun apply(request: RALoRAApplyRequest): LoraApplyResult =
        decodeOrThrow(
            LoraApplyResult.ADAPTER,
            RunAnywhereBridge.racLoraApplyProto(request.encode()),
            "racLoraApplyProto",
        )

    suspend fun remove(request: RALoRARemoveRequest): RALoRAState =
        decodeOrThrow(
            RALoRAState.ADAPTER,
            RunAnywhereBridge.racLoraRemoveProto(request.encode()),
            "racLoraRemoveProto",
        )

    suspend fun list(request: RALoRAState): RALoRAState =
        decodeOrThrow(
            RALoRAState.ADAPTER,
            RunAnywhereBridge.racLoraListProto(request.encode()),
            "racLoraListProto",
        )

    suspend fun state(request: RALoRAState): RALoRAState =
        decodeOrThrow(
            RALoRAState.ADAPTER,
            RunAnywhereBridge.racLoraStateProto(request.encode()),
            "racLoraStateProto",
        )

    suspend fun compatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult =
        decodeOrThrow(
            LoraCompatibilityResult.ADAPTER,
            RunAnywhereBridge.racLoraCompatibilityProto(config.encode()),
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

    // markDownloadCompleted(_:) / importAdapter(_:) were deleted:
    // LoraAdapterDownloadCompletedRequest/Result and LoraAdapterImportRequest/
    // Result were removed outright from idl/lora_options.proto
    // (lora-delete-download-import-bookkeeping). Adapter files are now
    // acquired exclusively through the models domain's download/import verbs;
    // this LoRA domain carries no download/import state of its own -- a
    // non-empty LoraAdapterCatalogEntry.local_path is the only "downloaded"
    // signal that survives. The corresponding C ABI entry points
    // (rac_lora_catalog_mark_download_completed_proto /
    // rac_lora_adapter_import_proto) are retired stubs that always report
    // RAC_ERROR_NOT_IMPLEMENTED. Mirrors Swift's
    // `CppBridge+LoraRegistry.swift`.
}
