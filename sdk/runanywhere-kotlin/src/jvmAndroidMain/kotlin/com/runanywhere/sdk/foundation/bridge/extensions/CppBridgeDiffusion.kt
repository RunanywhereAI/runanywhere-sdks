/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DiffusionConfig
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionProgress
import ai.runanywhere.proto.v1.DiffusionResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
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

private fun checkRc(rc: Int, operation: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$operation failed with rc=$rc")
    }
}

/**
 * Diffusion (image generation) facade over the `rac_diffusion_*` C ABI.
 * Swift currently has no `CppBridge+Diffusion.swift` (Apple-only feature),
 * but the Kotlin JNI bindings exist so we keep the bridge here.
 */
object CppBridgeDiffusion {
    @Volatile private var handle: Long = 0L

    @Volatile private var modelId: String? = null

    @Synchronized
    fun load(config: DiffusionConfig) {
        unload()
        val serviceHandle =
            RunAnywhereBridge.racDiffusionCreate(config.model_id.ifBlank { config.model_path })
        if (serviceHandle == 0L) {
            throw SDKException.operation("racDiffusionCreate returned 0")
        }
        if (config.model_path.isNotBlank()) {
            val rc = RunAnywhereBridge.racDiffusionInitialize(serviceHandle, config.model_path)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                RunAnywhereBridge.racDiffusionDestroy(serviceHandle)
                checkRc(rc, "racDiffusionInitialize")
            }
        }
        handle = serviceHandle
        modelId = config.model_id.ifBlank { config.model_path }
    }

    @Synchronized
    fun unload() {
        if (handle != 0L) RunAnywhereBridge.racDiffusionDestroy(handle)
        handle = 0L
        modelId = null
    }

    fun generate(prompt: String, options: DiffusionGenerationOptions?): DiffusionResult {
        val request = (options ?: DiffusionGenerationOptions()).copy(prompt = prompt)
        return decodeOrThrow(
            DiffusionResult.ADAPTER,
            RunAnywhereBridge.racDiffusionGenerateProto(
                requireHandle(),
                DiffusionGenerationOptions.ADAPTER.encode(request),
            ),
            "racDiffusionGenerateProto",
        )
    }

    fun generateWithProgress(
        prompt: String,
        options: DiffusionGenerationOptions?,
        onProgress: (DiffusionProgress) -> Boolean,
    ): DiffusionResult {
        val request = (options ?: DiffusionGenerationOptions()).copy(prompt = prompt)
        return decodeOrThrow(
            DiffusionResult.ADAPTER,
            RunAnywhereBridge.racDiffusionGenerateWithProgressProto(
                requireHandle(),
                DiffusionGenerationOptions.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onProgress(DiffusionProgress.ADAPTER.decode(bytes))
                },
            ),
            "racDiffusionGenerateWithProgressProto",
        )
    }

    fun cancel() {
        checkRc(RunAnywhereBridge.racDiffusionCancelProto(requireHandle()), "racDiffusionCancelProto")
    }

    fun isLoaded(): Boolean = handle != 0L

    fun currentModelId(): String? = modelId

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("Diffusion service not loaded")
}
