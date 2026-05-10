/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsRequest
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsResponse
import ai.runanywhere.proto.v1.VLMResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASDKEvent
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
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
 * Mirrors Swift CppBridge+VLM.swift. Wraps `rac_vlm_*_proto` C ABI.
 */
object CppBridgeVLM {
    @Volatile private var handle: Long = 0L

    @Synchronized
    fun loadResolvedArtifacts(
        modelId: String,
        primaryModelPath: String,
        visionProjectorPath: String,
    ): Int {
        destroy()
        val request =
            VLMLoadResolvedArtifactsRequest(
                model_id = modelId,
                primary_model_path = primaryModelPath,
                mmproj_path = visionProjectorPath.takeIf { it.isNotBlank() },
            )
        val response =
            decodeOrThrow(
                VLMLoadResolvedArtifactsResponse.ADAPTER,
                RunAnywhereBridge.racVlmComponentLoadResolvedArtifactsProto(
                    VLMLoadResolvedArtifactsRequest.ADAPTER.encode(request),
                ),
                "racVlmComponentLoadResolvedArtifactsProto",
            )
        if (response.result_code != RunAnywhereBridge.RAC_SUCCESS || response.handle == 0L) {
            return if (response.result_code != RunAnywhereBridge.RAC_SUCCESS) {
                response.result_code
            } else {
                RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
            }
        }
        handle = response.handle
        return RunAnywhereBridge.RAC_SUCCESS
    }

    @Synchronized
    fun destroy() {
        if (handle != 0L) RunAnywhereBridge.racVlmDestroy(handle)
        handle = 0L
    }

    fun isLoaded(): Boolean = handle != 0L

    fun cancel() {
        if (handle != 0L) RunAnywhereBridge.racVlmCancelProto(handle)
    }

    fun process(image: RAVLMImage, options: RAVLMGenerationOptions): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
            ),
            "racVlmProcessProto",
        )

    fun processStream(
        image: RAVLMImage,
        options: RAVLMGenerationOptions,
        onEvent: (RASDKEvent) -> Boolean,
    ): RAVLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessStreamProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onEvent(SDKEvent.ADAPTER.decode(bytes))
                },
            ),
            "racVlmProcessStreamProto",
        )

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("VLM service not loaded")
}
