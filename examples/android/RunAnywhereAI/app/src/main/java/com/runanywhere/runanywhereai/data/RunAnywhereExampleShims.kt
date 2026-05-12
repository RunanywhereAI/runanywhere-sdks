/*
 * Copyright 2026 RunAnywhere SDK Examples
 * SPDX-License-Identifier: Apache-2.0
 *
 * Example-app-side shims for SDK helpers that are not part of the canonical
 * cross-SDK public surface. Logic was previously hosted in
 * `RunAnywhere+Frameworks.kt`; it now lives here so the SDK module no
 * longer ships example-only utilities.
 */

package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.FrameworksForCapabilityRequest
import ai.runanywhere.proto.v1.FrameworksForCapabilityResponse
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.displayName

/**
 * Get all registered frameworks derived from available models.
 *
 * Example-app shim that reads directly from [CppBridgeModelRegistry], the
 * same path the deleted SDK extension used.
 */
suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> {
    check(isInitialized) { "SDK not initialized" }
    val all = CppBridgeModelRegistry.getAll()
    return all
        .map { it.framework }
        .distinct()
        .sortedBy { it.displayName }
}

/**
 * Get all registered frameworks that provide a specific capability.
 *
 * Calls the existing JNI surface
 * `RunAnywhereBridge.racRouterFrameworksForCapabilityProto` directly.
 */
suspend fun RunAnywhere.getFrameworksForCapability(capability: SDKComponent): List<InferenceFramework> {
    check(isInitialized) { "SDK not initialized" }

    val request = FrameworksForCapabilityRequest(component = capability)
    val responseBytes =
        try {
            RunAnywhereBridge.racRouterFrameworksForCapabilityProto(
                FrameworksForCapabilityRequest.ADAPTER.encode(request),
            )
        } catch (e: UnsatisfiedLinkError) {
            error("rac_router_frameworks_for_capability_proto unavailable: ${e.message}")
        } ?: return emptyList()

    val response =
        try {
            FrameworksForCapabilityResponse.ADAPTER.decode(responseBytes)
        } catch (e: Exception) {
            error("Failed to decode FrameworksForCapabilityResponse: ${e.message}")
        }
    return response.frameworks.sortedBy { it.displayName }
}

/**
 * Cross-platform parity helper. Kotlin's `registerModel` is synchronous
 * (writes through [CppBridgeModelRegistry] inline), so this is effectively
 * a no-op kept only for parity with Swift / RN / Web example code.
 */
suspend fun RunAnywhere.flushPendingRegistrations() {
    check(isInitialized) { "SDK not initialized" }
}
