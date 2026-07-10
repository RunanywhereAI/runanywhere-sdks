/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DiffusionGenerationRequest
import ai.runanywhere.proto.v1.DiffusionResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RADiffusionGenerationOptions
import com.runanywhere.sdk.public.types.RADiffusionResult

/** Thin facade over the lifecycle-owned diffusion proto ABI. */
object CppBridgeDiffusion {
    suspend fun generate(
        options: RADiffusionGenerationOptions,
        modelId: String? = null,
    ): RADiffusionResult {
        val request =
            DiffusionGenerationRequest(
                model_id = modelId.orEmpty(),
                options = options,
            )
        val payload =
            RunAnywhereBridge.racDiffusionGenerateLifecycleProto(
                DiffusionGenerationRequest.ADAPTER.encode(request),
            ) ?: throw SDKException.operation(
                "racDiffusionGenerateLifecycleProto returned null",
            )
        return try {
            DiffusionResult.ADAPTER.decode(payload)
        } catch (e: Exception) {
            throw SDKException.operation(
                "Failed to decode racDiffusionGenerateLifecycleProto result: ${e.message}",
                e,
            )
        }
    }
}
