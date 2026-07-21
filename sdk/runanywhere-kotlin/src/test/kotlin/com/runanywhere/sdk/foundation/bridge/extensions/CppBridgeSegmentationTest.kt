package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.SegmentationClassSummary
import ai.runanywhere.proto.v1.SegmentationImage
import ai.runanywhere.proto.v1.SegmentationOptions
import ai.runanywhere.proto.v1.SegmentationPixelFormat
import ai.runanywhere.proto.v1.SegmentationRequest
import ai.runanywhere.proto.v1.SegmentationResult
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.toByteString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class CppBridgeSegmentationTest {
    @Test
    fun `segment serializes the request and decodes the native result`() =
        runTest {
            val request =
                SegmentationRequest(
                    image =
                        SegmentationImage(
                            data_ = byteArrayOf(0x10, 0x20, 0x30).toByteString(),
                            width = 1,
                            height = 1,
                            pixel_format = SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
                        ),
                    options = SegmentationOptions(include_diagnostic_rgba = true),
                )
            val expected =
                SegmentationResult(
                    width = 1,
                    height = 1,
                    class_mask_u16_le = byteArrayOf(12, 0).toByteString(),
                    diagnostic_rgba = byteArrayOf(1, 2, 3, 0xff.toByte()).toByteString(),
                    class_summaries =
                        listOf(
                            SegmentationClassSummary(
                                class_id = 12,
                                pixel_count = 1,
                                fraction = 1f,
                                label = "person",
                            ),
                        ),
                    processing_time_ms = 7,
                    model_id = "segformer-b0",
                )
            var decodedRequest: SegmentationRequest? = null

            val result =
                CppBridgeSegmentation.segment(
                    request,
                    SegmentationLifecycleNativeBridge { payload ->
                        decodedRequest = SegmentationRequest.ADAPTER.decode(payload)
                        SegmentationResult.ADAPTER.encode(expected)
                    },
                )

            assertEquals(request, decodedRequest)
            assertEquals(expected, result)
        }

    @Test
    fun `segment maps a missing native payload to an SDK exception`() =
        runTest {
            val error =
                assertFailsWith<SDKException> {
                    CppBridgeSegmentation.segment(
                        SegmentationRequest(),
                        SegmentationLifecycleNativeBridge { null },
                    )
                }

            assertEquals(ErrorCode.ERROR_CODE_GENERATION_FAILED, error.code)
            assertTrue(error.message.orEmpty().contains("returned null"))
        }

    @Test
    fun `segment maps a native failure to an SDK exception`() =
        runTest {
            val error =
                assertFailsWith<SDKException> {
                    CppBridgeSegmentation.segment(
                        SegmentationRequest(),
                        SegmentationLifecycleNativeBridge {
                            throw IllegalStateException("native segmentation failed")
                        },
                    )
                }

            assertEquals(ErrorCode.ERROR_CODE_GENERATION_FAILED, error.code)
            assertIs<IllegalStateException>(error.cause)
            assertTrue(error.message.orEmpty().contains("native segmentation failed"))
        }

    @Test
    fun `segment maps a malformed result to an SDK exception`() =
        runTest {
            val error =
                assertFailsWith<SDKException> {
                    CppBridgeSegmentation.segment(
                        SegmentationRequest(),
                        SegmentationLifecycleNativeBridge {
                            byteArrayOf(0x1a, 0x02, 0x01)
                        },
                    )
                }

            assertEquals(ErrorCode.ERROR_CODE_GENERATION_FAILED, error.code)
            assertTrue(error.message.orEmpty().contains("Failed to decode"))
        }
}
