/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for the LoRA capability namespace.
 *
 * Mirrors Swift's `RunAnywhere.lora` (the `LoRA` value type in
 * `RunAnywhere+LoRA.swift`). All runtime + catalog ops delegate to
 * `CppBridgeLoRA` which wraps the generated `rac_lora_*_proto` C ABI.
 */

package com.runanywhere.sdk.public.extensions

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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoRA
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * JVM/Android backing object for [LoRANamespace]. Stateless; all calls
 * delegate to [CppBridgeLoRA] on `Dispatchers.IO`.
 */
internal object AndroidLoRANamespace : LoRANamespace {
    override suspend fun apply(request: LoRAApplyRequest): LoRAApplyResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.apply(request)
        }

    override suspend fun remove(request: LoRARemoveRequest): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.remove(request)
        }

    override suspend fun list(): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.list(LoRAState())
        }

    override suspend fun state(): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.state(LoRAState())
        }

    override suspend fun checkCompatibility(config: LoRAAdapterConfig): LoraCompatibilityResult =
        withContext(Dispatchers.IO) {
            try {
                CppBridgeLoRA.compatibility(config)
            } catch (e: Exception) {
                LoraCompatibilityResult(
                    is_compatible = false,
                    error_message = e.message.orEmpty(),
                )
            }
        }

    override suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.register(entry)
        }

    override suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest,
    ): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.listCatalog(request)
        }

    override suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.queryCatalog(query)
        }

    override suspend fun getCatalogEntry(
        request: LoraAdapterCatalogGetRequest,
    ): LoraAdapterCatalogGetResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.getCatalogEntry(request)
        }

    override suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoRA.markDownloadCompleted(request)
        }
}

actual val RunAnywhere.lora: LoRANamespace
    get() = AndroidLoRANamespace
