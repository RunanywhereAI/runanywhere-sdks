/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for framework discovery + queries.
 *
 * Wave H-5 (KOT-12): getFrameworksForCapability delegates to the commons
 * engine-router via rac_router_frameworks_for_capability_proto. The previous
 * SDKComponent -> ModelCategory -> framework mapping lived in Kotlin and
 * was deleted; commons now owns the canonical capability -> framework
 * resolution for every SDK.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.displayName
import ai.runanywhere.proto.v1.FrameworksForCapabilityRequest as ProtoFrameworksForCapabilityRequest
import ai.runanywhere.proto.v1.FrameworksForCapabilityResponse as ProtoFrameworksForCapabilityResponse

actual suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val all = CppBridgeModelRegistry.getAll()
    return all
        .map { it.framework }
        .distinct()
        .sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.getFrameworksForCapability(capability: SDKComponent): List<InferenceFramework> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val request = ProtoFrameworksForCapabilityRequest(component = capability)
    val responseBytes =
        try {
            RunAnywhereBridge.racRouterFrameworksForCapabilityProto(
                ProtoFrameworksForCapabilityRequest.ADAPTER.encode(request),
            )
        } catch (e: UnsatisfiedLinkError) {
            throw SDKException.notInitialized(
                "rac_router_frameworks_for_capability_proto unavailable: ${e.message}",
            )
        } ?: return emptyList()

    val response =
        try {
            ProtoFrameworksForCapabilityResponse.ADAPTER.decode(responseBytes)
        } catch (e: Exception) {
            throw SDKException.notInitialized(
                "Failed to decode FrameworksForCapabilityResponse: ${e.message}",
            )
        }
    return response.frameworks.sortedBy { it.displayName }
}

actual suspend fun RunAnywhere.flushPendingRegistrations() {
    // Kotlin's registerModel is synchronous (CppBridgeModelRegistry.save).
    // Nothing to flush; this exists for cross-platform parity.
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
}

actual suspend fun RunAnywhere.discoverDownloadedModels() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    refreshModelRegistry(
        includeRemoteCatalog = false,
        rescanLocal = true,
        pruneOrphans = false,
    )
}
