/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for the LoRA capability namespace.
 *
 * Mirrors Swift's `RunAnywhere.lora` (the `LoRA` value type in
 * `RunAnywhere+LoRA.swift`). All runtime + catalog ops delegate to
 * `CppBridgeLoraRegistry` which wraps the generated `rac_lora_*_proto` C ABI.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LoRAApplyResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraRegistry
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALoRAAdapterConfig
import com.runanywhere.sdk.public.types.RALoRAApplyRequest
import com.runanywhere.sdk.public.types.RALoRARemoveRequest
import com.runanywhere.sdk.public.types.RALoRAState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * JVM/Android backing object for [LoRANamespace]. Stateless; all calls
 * delegate to [CppBridgeLoraRegistry] on `Dispatchers.IO`.
 */
internal object AndroidLoRANamespace : LoRANamespace {
    override suspend fun apply(request: RALoRAApplyRequest): LoRAApplyResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.apply(request)
        }

    override suspend fun remove(request: RALoRARemoveRequest): RALoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.remove(request)
        }

    override suspend fun list(): RALoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.list(RALoRAState())
        }

    override suspend fun state(): RALoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.state(RALoRAState())
        }

    override suspend fun checkCompatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult =
        withContext(Dispatchers.IO) {
            try {
                CppBridgeLoraRegistry.compatibility(config)
            } catch (e: Exception) {
                LoraCompatibilityResult(
                    is_compatible = false,
                    error_message = e.message.orEmpty(),
                )
            }
        }

    override suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.register(entry)
        }

    override suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest,
    ): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.listCatalog(request)
        }

    override suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.queryCatalog(query)
        }

    override suspend fun getCatalogEntry(
        request: LoraAdapterCatalogGetRequest,
    ): LoraAdapterCatalogGetResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.getCatalogEntry(request)
        }

    override suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.markDownloadCompleted(request)
        }
}

actual val RunAnywhere.lora: LoRANamespace
    get() = AndroidLoRANamespace
