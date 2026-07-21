/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.VocoderRequest
import com.runanywhere.sdk.public.extensions.VocoderResult
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import ai.runanywhere.proto.v1.VocoderRequest as WireVocoderRequest
import ai.runanywhere.proto.v1.VocoderResult as WireVocoderResult

/** Injectable only so the proto boundary can be verified without loading JNI. */
internal fun interface VocoderLifecycleNativeBridge {
    fun vocode(requestProto: ByteArray): ByteArray?
}

private object JniVocoderLifecycleNativeBridge : VocoderLifecycleNativeBridge {
    override fun vocode(requestProto: ByteArray): ByteArray? =
        RunAnywhereBridge.racVocoderVocodeLifecycleProto(requestProto)
}

/** Thin facade over the lifecycle-owned vocoder proto ABI. */
object CppBridgeVocoder {
    suspend fun vocode(
        request: VocoderRequest,
        expectedModelId: String,
    ): VocoderResult = vocode(request, expectedModelId, JniVocoderLifecycleNativeBridge)

    internal suspend fun vocode(
        request: VocoderRequest,
        expectedModelId: String,
        nativeBridge: VocoderLifecycleNativeBridge,
    ): VocoderResult {
        if (expectedModelId.isBlank()) {
            throw processingFailure("The lifecycle-loaded vocoder model id is empty")
        }

        // Copy before validating so a caller cannot mutate the array between
        // validation and serialization on another coroutine/thread.
        val samples = request.melSpectrogram.copyOf()
        validateRequest(request, samples)
        val wireRequest =
            WireVocoderRequest(
                mel_spectrogram_f32_le = encodeFloat32LittleEndian(samples).toByteString(),
                batch_size = request.batchSize,
                mel_bin_count = request.melBinCount,
                frame_count = request.frameCount,
            )

        val payload =
            try {
                withContext(Dispatchers.IO) {
                    nativeBridge.vocode(WireVocoderRequest.ADAPTER.encode(wireRequest))
                }
            } catch (error: SDKException) {
                throw error
            } catch (error: Throwable) {
                throw processingFailure(
                    "Vocoder processing failed: ${error.message ?: error::class.java.simpleName}",
                    error,
                )
            } ?: throw processingFailure("racVocoderVocodeLifecycleProto returned null")

        val wireResult =
            try {
                WireVocoderResult.ADAPTER.decode(payload)
            } catch (error: Exception) {
                throw processingFailure(
                    "Failed to decode racVocoderVocodeLifecycleProto result: ${error.message}",
                    error,
                )
            }

        return validateAndConvertResult(wireResult, request, expectedModelId)
    }
}

private const val FLOAT32_BYTE_COUNT = Float.SIZE_BYTES

private fun validateRequest(
    request: VocoderRequest,
    samples: FloatArray,
) {
    requirePositiveDimension("VocoderRequest.batchSize", request.batchSize)
    requirePositiveDimension("VocoderRequest.melBinCount", request.melBinCount)
    requirePositiveDimension("VocoderRequest.frameCount", request.frameCount)

    val expectedElementCount =
        checkedInputElementCount(
            request.batchSize,
            request.melBinCount,
            request.frameCount,
        )
    if (samples.size != expectedElementCount) {
        throw SDKException.validationFailed(
            fieldPath = "VocoderRequest.melSpectrogram",
            message =
                "melSpectrogram must contain exactly $expectedElementCount values " +
                    "for [${request.batchSize}, ${request.melBinCount}, ${request.frameCount}] " +
                    "(got ${samples.size})",
        )
    }

    val nonFiniteIndex = samples.indexOfFirst { !it.isFinite() }
    if (nonFiniteIndex >= 0) {
        throw SDKException.validationFailed(
            fieldPath = "VocoderRequest.melSpectrogram[$nonFiniteIndex]",
            message = "melSpectrogram[$nonFiniteIndex] must be finite",
        )
    }
}

private fun requirePositiveDimension(
    fieldPath: String,
    value: Int,
) {
    if (value <= 0) {
        throw SDKException.validationFailed(
            fieldPath = fieldPath,
            message = "${fieldPath.substringAfterLast('.')} must be greater than zero (got $value)",
        )
    }
}

private fun checkedInputElementCount(
    batchSize: Int,
    melBinCount: Int,
    frameCount: Int,
): Int {
    val count = checkedProduct(batchSize, melBinCount, frameCount)
    if (count == null || count > Int.MAX_VALUE / FLOAT32_BYTE_COUNT) {
        throw SDKException.validationFailed(
            fieldPath = "VocoderRequest.melSpectrogram",
            message = "VocoderRequest dimensions exceed the supported in-memory payload size",
        )
    }
    return count.toInt()
}

private fun encodeFloat32LittleEndian(samples: FloatArray): ByteArray {
    val buffer =
        ByteBuffer
            .allocate(Math.multiplyExact(samples.size, FLOAT32_BYTE_COUNT))
            .order(ByteOrder.LITTLE_ENDIAN)
    for (sample in samples) {
        buffer.putFloat(sample)
    }
    return buffer.array()
}

private fun validateAndConvertResult(
    result: WireVocoderResult,
    request: VocoderRequest,
    expectedModelId: String,
): VocoderResult {
    requirePositiveResult("batch_size", result.batch_size)
    requirePositiveResult("channel_count", result.channel_count)
    requirePositiveResult("sample_count", result.sample_count)
    requirePositiveResult("sample_rate_hz", result.sample_rate_hz)
    requirePositiveResult("hop_length", result.hop_length)

    if (result.channel_count != 1) {
        throw processingFailure("Invalid vocoder result: channel_count must equal 1")
    }
    if (result.processing_time_ms < 0) {
        throw processingFailure("Invalid vocoder result: processing_time_ms must be non-negative")
    }
    if (result.model_id.isBlank()) {
        throw processingFailure("Invalid vocoder result: model_id is empty")
    }
    if (result.model_id != expectedModelId) {
        throw processingFailure(
            "Invalid vocoder result: model_id '${result.model_id}' does not match " +
                "lifecycle model '$expectedModelId'",
        )
    }
    if (result.batch_size != request.batchSize) {
        throw processingFailure(
            "Invalid vocoder result: batch_size ${result.batch_size} does not match " +
                "request batchSize ${request.batchSize}",
        )
    }

    val expectedSampleCount = checkedProduct(request.frameCount, result.hop_length)
    if (expectedSampleCount == null || expectedSampleCount > Int.MAX_VALUE) {
        throw processingFailure("Invalid vocoder result: frame_count * hop_length overflows Int")
    }
    if (result.sample_count != expectedSampleCount.toInt()) {
        throw processingFailure(
            "Invalid vocoder result: sample_count ${result.sample_count} does not equal " +
                "frameCount ${request.frameCount} * hop_length ${result.hop_length}",
        )
    }

    val sampleBytes = result.samples_f32_le.toByteArray()
    if (sampleBytes.size % FLOAT32_BYTE_COUNT != 0) {
        throw processingFailure(
            "Invalid vocoder result: samples_f32_le byte length ${sampleBytes.size} is not divisible by 4",
        )
    }
    val expectedElementCount =
        checkedProduct(result.batch_size, result.channel_count, result.sample_count)
    if (expectedElementCount == null || expectedElementCount > Int.MAX_VALUE / FLOAT32_BYTE_COUNT) {
        throw processingFailure("Invalid vocoder result: output dimensions exceed the supported payload size")
    }
    val actualElementCount = sampleBytes.size / FLOAT32_BYTE_COUNT
    if (actualElementCount != expectedElementCount.toInt()) {
        throw processingFailure(
            "Invalid vocoder result: samples_f32_le contains $actualElementCount values, " +
                "expected $expectedElementCount for " +
                "[${result.batch_size}, ${result.channel_count}, ${result.sample_count}]",
        )
    }

    val samples = decodeFloat32LittleEndian(sampleBytes)
    val nonFiniteIndex = samples.indexOfFirst { !it.isFinite() }
    if (nonFiniteIndex >= 0) {
        throw processingFailure("Invalid vocoder result: samples[$nonFiniteIndex] is not finite")
    }

    return VocoderResult(
        samples = samples,
        batchSize = result.batch_size,
        channelCount = result.channel_count,
        sampleCount = result.sample_count,
        sampleRateHz = result.sample_rate_hz,
        hopLength = result.hop_length,
        processingTimeMs = result.processing_time_ms,
        modelId = result.model_id,
    )
}

private fun requirePositiveResult(
    fieldName: String,
    value: Int,
) {
    if (value <= 0) {
        throw processingFailure("Invalid vocoder result: $fieldName must be greater than zero")
    }
}

private fun checkedProduct(vararg values: Int): Long? =
    try {
        values.fold(1L) { product, value -> Math.multiplyExact(product, value.toLong()) }
    } catch (_: ArithmeticException) {
        null
    }

private fun decodeFloat32LittleEndian(bytes: ByteArray): FloatArray {
    val floatBuffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
    return FloatArray(floatBuffer.remaining()).also(floatBuffer::get)
}

private fun processingFailure(
    message: String,
    cause: Throwable? = null,
): SDKException =
    SDKException.make(
        code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
        message = message,
        category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
        cause = cause,
        shouldLog = false,
    )
