package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.extensions.VocoderRequest
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.toByteString
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.test.fail
import ai.runanywhere.proto.v1.VocoderRequest as WireVocoderRequest
import ai.runanywhere.proto.v1.VocoderResult as WireVocoderResult

class CppBridgeVocoderTest {
    @Test
    fun `vocode encodes little endian float32 and returns validated typed samples`() =
        runTest {
            val request =
                VocoderRequest(
                    melSpectrogram = floatArrayOf(1f, -2.5f, Float.MIN_VALUE, 0f),
                    batchSize = 1,
                    melBinCount = 2,
                    frameCount = 2,
                )
            val expectedSamples = floatArrayOf(0.1f, -0.2f, 0.3f, -0.4f)
            var decodedRequest: WireVocoderRequest? = null

            val result =
                CppBridgeVocoder.vocode(
                    request = request,
                    expectedModelId = "bigvgan",
                    nativeBridge =
                        VocoderLifecycleNativeBridge { payload ->
                            decodedRequest = WireVocoderRequest.ADAPTER.decode(payload)
                            validWireResult(samples = expectedSamples).encode()
                        },
                )

            val wire = decodedRequest ?: fail("native bridge did not receive the request")
            assertEquals(1, wire.batch_size)
            assertEquals(2, wire.mel_bin_count)
            assertEquals(2, wire.frame_count)
            assertContentEquals(
                byteArrayOf(
                    0x00,
                    0x00,
                    0x80.toByte(),
                    0x3f,
                    0x00,
                    0x00,
                    0x20,
                    0xc0.toByte(),
                    0x01,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                ),
                wire.mel_spectrogram_f32_le.toByteArray(),
            )
            assertContentEquals(expectedSamples, result.samples)
            assertEquals(1, result.batchSize)
            assertEquals(1, result.channelCount)
            assertEquals(4, result.sampleCount)
            assertEquals(22_050, result.sampleRateHz)
            assertEquals(2, result.hopLength)
            assertEquals(7L, result.processingTimeMs)
            assertEquals("bigvgan", result.modelId)
        }

    @Test
    fun `vocode rejects invalid request dimensions shape overflow and nonfinite values before JNI`() =
        runTest {
            val cases =
                listOf(
                    InvalidRequestCase(
                        request = request(batchSize = 0),
                        fieldPath = "VocoderRequest.batchSize",
                    ),
                    InvalidRequestCase(
                        request = request(melSpectrogram = floatArrayOf(0f)),
                        fieldPath = "VocoderRequest.melSpectrogram",
                    ),
                    InvalidRequestCase(
                        request = request(melSpectrogram = floatArrayOf(0f, Float.NaN, 0f, 0f)),
                        fieldPath = "VocoderRequest.melSpectrogram[1]",
                    ),
                    InvalidRequestCase(
                        request =
                            VocoderRequest(
                                melSpectrogram = floatArrayOf(),
                                batchSize = Int.MAX_VALUE,
                                melBinCount = Int.MAX_VALUE,
                                frameCount = Int.MAX_VALUE,
                            ),
                        fieldPath = "VocoderRequest.melSpectrogram",
                    ),
                )

            for (case in cases) {
                var called = false
                val error =
                    assertFailsWith<SDKException> {
                        CppBridgeVocoder.vocode(
                            request = case.request,
                            expectedModelId = "bigvgan",
                            nativeBridge =
                                VocoderLifecycleNativeBridge {
                                    called = true
                                    validWireResult().encode()
                                },
                        )
                    }

                assertEquals(ErrorCode.ERROR_CODE_INVALID_ARGUMENT, error.code)
                assertEquals(ErrorCategory.ERROR_CATEGORY_VALIDATION, error.category)
                assertEquals(case.fieldPath, error.fieldPath)
                assertEquals(false, called)
            }
        }

    @Test
    fun `vocode rejects malformed native metadata shape bytes and samples`() =
        runTest {
            val validRequest = request()
            val cases =
                listOf(
                    InvalidResultCase(validWireResult().copy(batch_size = 0), "batch_size"),
                    InvalidResultCase(validWireResult().copy(channel_count = 0), "channel_count"),
                    InvalidResultCase(
                        validWireResult(samples = FloatArray(8)).copy(channel_count = 2),
                        "channel_count must equal 1",
                    ),
                    InvalidResultCase(validWireResult().copy(sample_count = 0), "sample_count"),
                    InvalidResultCase(validWireResult().copy(sample_rate_hz = 0), "sample_rate_hz"),
                    InvalidResultCase(validWireResult().copy(hop_length = 0), "hop_length"),
                    InvalidResultCase(validWireResult().copy(processing_time_ms = -1), "processing_time_ms"),
                    InvalidResultCase(validWireResult().copy(model_id = ""), "model_id"),
                    InvalidResultCase(validWireResult().copy(model_id = "other"), "model_id"),
                    InvalidResultCase(validWireResult().copy(batch_size = 2), "batch_size"),
                    InvalidResultCase(validWireResult().copy(sample_count = 3), "frameCount"),
                    InvalidResultCase(
                        validWireResult().copy(
                            samples_f32_le = byteArrayOf(0, 0, 0).toByteString(),
                        ),
                        "not divisible by 4",
                    ),
                    InvalidResultCase(
                        validWireResult().copy(
                            samples_f32_le = float32LittleEndian(floatArrayOf(0f, 0f, 0f)),
                        ),
                        "contains 3 values",
                    ),
                    InvalidResultCase(
                        validWireResult(
                            samples = floatArrayOf(0f, Float.POSITIVE_INFINITY, 0f, 0f),
                        ),
                        "not finite",
                    ),
                )

            for (case in cases) {
                val error =
                    assertFailsWith<SDKException> {
                        CppBridgeVocoder.vocode(
                            request = validRequest,
                            expectedModelId = "bigvgan",
                            nativeBridge = VocoderLifecycleNativeBridge { case.result.encode() },
                        )
                    }

                assertEquals(ErrorCode.ERROR_CODE_PROCESSING_FAILED, error.code)
                assertEquals(ErrorCategory.ERROR_CATEGORY_INTERNAL, error.category)
                assertTrue(
                    error.message.orEmpty().contains(case.messageFragment),
                    "Expected '${error.message}' to contain '${case.messageFragment}'",
                )
            }
        }

    @Test
    fun `vocode maps null thrown and malformed native payloads to processing failures`() =
        runTest {
            val bridges =
                listOf(
                    VocoderLifecycleNativeBridge { null },
                    VocoderLifecycleNativeBridge { throw IllegalStateException("native vocoder failed") },
                    VocoderLifecycleNativeBridge { byteArrayOf(0x0a, 0x02, 0x01) },
                )

            for (bridge in bridges) {
                val error =
                    assertFailsWith<SDKException> {
                        CppBridgeVocoder.vocode(request(), "bigvgan", bridge)
                    }
                assertEquals(ErrorCode.ERROR_CODE_PROCESSING_FAILED, error.code)
                assertEquals(ErrorCategory.ERROR_CATEGORY_INTERNAL, error.category)
            }
        }

    @Test
    fun `vocode preserves an SDK exception thrown by the native bridge`() =
        runTest {
            val expected = SDKException.modelNotLoaded("bigvgan")
            val actual =
                assertFailsWith<SDKException> {
                    CppBridgeVocoder.vocode(
                        request(),
                        "bigvgan",
                        VocoderLifecycleNativeBridge { throw expected },
                    )
                }

            assertIs<SDKException>(actual)
            assertTrue(actual === expected)
        }

    private fun request(
        melSpectrogram: FloatArray = floatArrayOf(0f, 0f, 0f, 0f),
        batchSize: Int = 1,
    ): VocoderRequest =
        VocoderRequest(
            melSpectrogram = melSpectrogram,
            batchSize = batchSize,
            melBinCount = 2,
            frameCount = 2,
        )

    private fun validWireResult(
        samples: FloatArray = floatArrayOf(0f, 0f, 0f, 0f),
    ): WireVocoderResult =
        WireVocoderResult(
            samples_f32_le = float32LittleEndian(samples),
            batch_size = 1,
            channel_count = 1,
            sample_count = 4,
            sample_rate_hz = 22_050,
            hop_length = 2,
            processing_time_ms = 7,
            model_id = "bigvgan",
        )

    private fun WireVocoderResult.encode(): ByteArray = WireVocoderResult.ADAPTER.encode(this)

    private fun float32LittleEndian(values: FloatArray): okio.ByteString {
        val buffer =
            ByteBuffer
                .allocate(values.size * Float.SIZE_BYTES)
                .order(ByteOrder.LITTLE_ENDIAN)
        values.forEach(buffer::putFloat)
        return buffer.array().toByteString()
    }

    private data class InvalidRequestCase(
        val request: VocoderRequest,
        val fieldPath: String,
    )

    private data class InvalidResultCase(
        val result: WireVocoderResult,
        val messageFragment: String,
    )
}
