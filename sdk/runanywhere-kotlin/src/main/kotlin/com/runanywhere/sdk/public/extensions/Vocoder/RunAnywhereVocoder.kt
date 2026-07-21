/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVocoder
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

/**
 * A contiguous float32 mel spectrogram in `[batch, melBin, frame]` order.
 *
 * [melSpectrogram] must contain exactly
 * `batchSize * melBinCount * frameCount` finite values.
 */
data class VocoderRequest(
    val melSpectrogram: FloatArray,
    val batchSize: Int,
    val melBinCount: Int,
    val frameCount: Int,
)

/** A contiguous float32 waveform returned in `[batch, channel, sample]` order. */
data class VocoderResult(
    val samples: FloatArray,
    val batchSize: Int,
    val channelCount: Int,
    val sampleCount: Int,
    val sampleRateHz: Int,
    val hopLength: Int,
    val processingTimeMs: Long,
    val modelId: String,
)

/**
 * Convert a mel spectrogram into waveform samples with the lifecycle-loaded
 * [ModelCategory.MODEL_CATEGORY_VOCODER] model.
 *
 * This call neither downloads nor loads a model. Register and load the
 * vocoder first; commons resolves its lifecycle-owned service and routes the
 * request to the selected engine.
 */
suspend fun RunAnywhere.vocode(request: VocoderRequest): VocoderResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK")
    }
    ensureServicesReady()
    val modelId =
        requireVocoderModelLoaded(
            loadedModelSnapshot(ModelCategory.MODEL_CATEGORY_VOCODER),
        )
    return CppBridgeVocoder.vocode(request, modelId)
}

internal fun requireVocoderModelLoaded(snapshot: CurrentModelResult): String {
    if (!snapshot.found) {
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
            message = "Vocoder model not loaded",
            category = ErrorCategory.ERROR_CATEGORY_COMPONENT,
            shouldLog = false,
        )
    }
    if (snapshot.model_id.isBlank()) {
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
            message = "Loaded vocoder snapshot has no model ID",
            category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
            shouldLog = false,
        )
    }
    return snapshot.model_id
}
