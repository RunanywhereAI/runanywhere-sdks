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
object CppBridgeLoRA {
    private fun nativeCatalogUnavailable(
        operation: String,
        cause: UnsatisfiedLinkError,
    ): String = "$operation native JNI symbol is unavailable: ${cause.message.orEmpty()}"

    fun apply(request: RALoRAApplyRequest): LoRAApplyResult {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoRAApplyResult.ADAPTER,
            RunAnywhereBridge.racLoraApplyProto(
                CppBridgeLLM.getHandle(),
                LoRAApplyRequest.ADAPTER.encode(request),
            ),
            "racLoraApplyProto",
        )
    }

    fun remove(request: RALoRARemoveRequest): RALoRAState {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraRemoveProto(
                CppBridgeLLM.getHandle(),
                LoRARemoveRequest.ADAPTER.encode(request),
            ),
            "racLoraRemoveProto",
        )
    }

    fun list(request: RALoRAState): RALoRAState {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraListProto(
                CppBridgeLLM.getHandle(),
                LoRAState.ADAPTER.encode(request),
            ),
            "racLoraListProto",
        )
    }

    fun state(request: RALoRAState): RALoRAState {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraStateProto(
                CppBridgeLLM.getHandle(),
                LoRAState.ADAPTER.encode(request),
            ),
            "racLoraStateProto",
        )
    }

    fun compatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoraCompatibilityResult.ADAPTER,
            RunAnywhereBridge.racLoraCompatibilityProto(
                CppBridgeLLM.getHandle(),
                LoRAAdapterConfig.ADAPTER.encode(config),
            ),
            "racLoraCompatibilityProto",
        )
    }

    fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        decodeOrThrow(
            LoraAdapterCatalogEntry.ADAPTER,
            RunAnywhereBridge.racLoraRegisterProto(LoraAdapterCatalogEntry.ADAPTER.encode(entry)),
            "racLoraRegisterProto",
        )

    fun listCatalog(request: LoraAdapterCatalogListRequest): LoraAdapterCatalogListResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogListResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogListProto(
                    LoraAdapterCatalogListRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogListProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogListResult(
                success = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogListProto", e),
            )
        }

    fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogListResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogQueryProto(
                    LoraAdapterCatalogQuery.ADAPTER.encode(query),
                ),
                "racLoraCatalogQueryProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogListResult(
                success = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogQueryProto", e),
            )
        }

    fun getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogGetResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogGetProto(
                    LoraAdapterCatalogGetRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogGetProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogGetResult(
                found = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogGetProto", e),
            )
        }

    fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        try {
            decodeOrThrow(
                LoraAdapterDownloadCompletedResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogMarkDownloadCompletedProto(
                    LoraAdapterDownloadCompletedRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogMarkDownloadCompletedProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterDownloadCompletedResult(
                success = false,
                persisted = false,
                error_message =
                    nativeCatalogUnavailable("racLoraCatalogMarkDownloadCompletedProto", e),
            )
        }
}
