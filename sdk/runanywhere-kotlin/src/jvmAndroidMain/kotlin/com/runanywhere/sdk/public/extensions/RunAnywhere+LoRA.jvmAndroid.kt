/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for generated LoRA service operations.
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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraProto
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual class LoRA internal actual constructor() {
    actual suspend fun apply(request: LoRAApplyRequest): LoRAApplyResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.apply(request)
        }

    actual suspend fun remove(request: LoRARemoveRequest): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.remove(request)
        }

    actual suspend fun list(request: LoRAState): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.list(request)
        }

    actual suspend fun state(request: LoRAState): LoRAState =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.state(request)
        }

    actual suspend fun checkCompatibility(config: LoRAAdapterConfig): LoraCompatibilityResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.compatibility(config)
        }

    actual suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.register(entry)
        }

    actual suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest,
    ): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.listCatalog(request)
        }

    actual suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.queryCatalog(query)
        }

    actual suspend fun getCatalogEntry(
        request: LoraAdapterCatalogGetRequest,
    ): LoraAdapterCatalogGetResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.getCatalogEntry(request)
        }

    actual suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.markDownloadCompleted(request)
        }
}

private val LoRASingleton = LoRA()

actual val RunAnywhere.lora: LoRA
    get() = LoRASingleton
