/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SegmentationRequest
import ai.runanywhere.proto.v1.SegmentationResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASegmentationRequest
import com.runanywhere.sdk.public.types.RASegmentationResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Injectable only so the proto boundary can be verified without loading JNI. */
internal fun interface SegmentationLifecycleNativeBridge {
    fun segment(requestProto: ByteArray): ByteArray?
}

private object JniSegmentationLifecycleNativeBridge : SegmentationLifecycleNativeBridge {
    override fun segment(requestProto: ByteArray): ByteArray? =
        RunAnywhereBridge.racSegmentationSegmentLifecycleProto(requestProto)
}

/** Thin facade over the lifecycle-owned semantic-segmentation proto ABI. */
object CppBridgeSegmentation {
    suspend fun segment(request: RASegmentationRequest): RASegmentationResult =
        segment(request, JniSegmentationLifecycleNativeBridge)

    internal suspend fun segment(
        request: RASegmentationRequest,
        nativeBridge: SegmentationLifecycleNativeBridge,
    ): RASegmentationResult {
        val payload =
            try {
                withContext(Dispatchers.IO) {
                    nativeBridge.segment(SegmentationRequest.ADAPTER.encode(request))
                }
            } catch (error: SDKException) {
                throw error
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw SDKException.operation(
                    "Semantic segmentation failed: ${error.message ?: error::class.java.simpleName}",
                    error,
                )
            } ?: throw SDKException.operation(
                "racSegmentationSegmentLifecycleProto returned null",
            )

        return try {
            SegmentationResult.ADAPTER.decode(payload)
        } catch (error: Exception) {
            throw SDKException.operation(
                "Failed to decode racSegmentationSegmentLifecycleProto result: ${error.message}",
                error,
            )
        }
    }
}
