/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ModelCompatibilityRequest
import ai.runanywhere.proto.v1.ModelCompatibilityResult
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/** Thin generated-proto facade over the canonical commons compatibility ABI. */
object CppBridgeModelCompatibility {
    fun check(request: ModelCompatibilityRequest): ModelCompatibilityResult? {
        val bytes =
            RunAnywhereBridge.racModelCompatibilityCheckProto(
                ModelCompatibilityRequest.ADAPTER.encode(request),
            ) ?: return null
        return try {
            ModelCompatibilityResult.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                "CppBridgeModelCompatibility",
                "Failed to decode compatibility result: ${e.message}",
            )
            null
        }
    }
}
