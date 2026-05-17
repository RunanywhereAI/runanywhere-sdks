/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * OkHttpHttpTransportResumeTest.kt
 *
 * pass2-syn-120 regression: asserts that `OkHttpHttpTransport.executeResumeRequest`
 * fulfils its half of the cross-SDK resume contract.
 *
 *   1. The outgoing HTTP request must carry `Range: bytes=N-` so the server
 *      knows to serve a partial body.
 *   2. The returned `StreamResponse.headers` must include the synthetic
 *      `X-RAC-Range-Honored` marker (`true` for 206, `false` for 200), so
 *      the C++ `rac_http_download_execute` resume-fallback can detect the
 *      Range-ignored case and rewrite the destination file in shift-left
 *      recovery mode.
 *
 * The test does NOT exercise the JNI body-callback path (deliverChunkNative
 * is an external function provided by the C++ JNI library; loading it from
 * a host-side JVM unit test would require the full Android stack). The
 * resume-contract guarantees we verify here are header-shape only.
 */

package com.runanywhere.sdk.httptransport

import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.atomic.AtomicReference

class OkHttpHttpTransportResumeTest {
    /**
     * Captures the request that flowed through the interceptor so the test
     * can assert on outgoing headers. Set per-test.
     */
    private val capturedRange = AtomicReference<String?>(null)

    /**
     * Stub status code returned by the interceptor. 206 simulates the
     * normal Range-honored case, 200 simulates the CDN/proxy that ignored
     * the Range header.
     */
    private val stubStatusCode = AtomicReference(206)

    @Before
    fun setUp() {
        capturedRange.set(null)
        stubStatusCode.set(206)

        // Install a custom OkHttp client whose only interceptor:
        //   - captures the outbound Range header (assertion target #1)
        //   - returns an EMPTY body with the configured status code
        // An empty body means drainBody() reads -1 immediately and never
        // calls deliverChunkNative (the JNI external symbol). This keeps
        // the test runnable on a plain JVM unit-test classpath.
        val client =
            OkHttpClient
                .Builder()
                .addInterceptor(
                    Interceptor { chain ->
                        val req = chain.request()
                        capturedRange.set(req.header("Range"))
                        Response
                            .Builder()
                            .request(req)
                            .protocol(Protocol.HTTP_1_1)
                            .code(stubStatusCode.get())
                            .message(
                                when (stubStatusCode.get()) {
                                    206 -> "Partial Content"
                                    200 -> "OK"
                                    else -> "Stubbed"
                                },
                            ).body("".toResponseBody("application/octet-stream".toMediaType()))
                            .build()
                    },
                ).build()
        OkHttpHttpTransport.setHttpClient(client)
    }

    @After
    fun tearDown() {
        OkHttpHttpTransport.setHttpClient(null)
        capturedRange.set(null)
    }

    /**
     * Assertion target #1: `executeResumeRequest` must attach
     * `Range: bytes=N-` to the outgoing request whenever
     * `resumeFromByte > 0`.
     *
     * Assertion target #2: when the server honored the Range (HTTP 206),
     * the synthetic `X-RAC-Range-Honored=true` marker must be present in
     * the response headers.
     */
    @Test
    fun executeResumeRequest_populates_range_header_and_emits_range_honored_true_on_206() {
        stubStatusCode.set(206)

        val response =
            OkHttpHttpTransport.executeResumeRequest(
                method = "GET",
                url = "http://localhost.invalid/payload",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 5_000L,
                resumeFromByte = 1024L,
                nativeCallback = 0L,
                nativeUserData = 0L,
            )

        // Transport itself succeeded (no JNI was invoked because body was empty).
        assertEquals(206, response.statusCode)
        assertNull("transport must not surface an error", response.errorMessage)
        assertTrue(
            "Range header must be present on outgoing resume request",
            capturedRange.get() == "bytes=1024-",
        )

        // Convert flat [name, value, name, value, ...] header array to a map for assertion.
        val headers = flatToMap(response.headers)
        val marker = headers["X-RAC-Range-Honored"]
        assertNotNull("X-RAC-Range-Honored marker must be present on resume responses", marker)
        assertEquals("Range-honored marker must be 'true' for HTTP 206", "true", marker)
    }

    /**
     * Assertion target #3: when the server IGNORED the Range header and
     * replied with HTTP 200 (full body), the synthetic
     * `X-RAC-Range-Honored=false` marker must be emitted so the C++
     * download runner can fire its shift-left recovery path.
     */
    @Test
    fun executeResumeRequest_emits_range_honored_false_when_server_returns_200() {
        stubStatusCode.set(200)

        val response =
            OkHttpHttpTransport.executeResumeRequest(
                method = "GET",
                url = "http://localhost.invalid/payload",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 5_000L,
                resumeFromByte = 2048L,
                nativeCallback = 0L,
                nativeUserData = 0L,
            )

        assertEquals(200, response.statusCode)
        assertEquals(
            "Range header must still be on the wire even if the server ignores it",
            "bytes=2048-",
            capturedRange.get(),
        )

        val headers = flatToMap(response.headers)
        val marker = headers["X-RAC-Range-Honored"]
        assertNotNull("X-RAC-Range-Honored marker must be present even on 200", marker)
        assertEquals("Range-honored marker must be 'false' for HTTP 200", "false", marker)
    }

    /**
     * Negative case: a non-resume (resumeFromByte == 0) call through
     * `executeStreamingRequest` must NOT carry a Range header AND must NOT
     * emit the synthetic `X-RAC-Range-Honored` marker. Guards against
     * accidentally tagging every streaming response.
     */
    @Test
    fun executeStreamingRequest_does_not_set_range_or_emit_marker() {
        stubStatusCode.set(200)

        val response =
            OkHttpHttpTransport.executeStreamingRequest(
                method = "GET",
                url = "http://localhost.invalid/payload",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 5_000L,
                nativeCallback = 0L,
                nativeUserData = 0L,
            )

        assertEquals(200, response.statusCode)
        assertNull("non-resume request must not carry Range header", capturedRange.get())
        val headers = flatToMap(response.headers)
        assertNull(
            "non-resume responses must not include X-RAC-Range-Honored",
            headers["X-RAC-Range-Honored"],
        )
    }

    private fun flatToMap(flat: Array<String>): Map<String, String> {
        val out = HashMap<String, String>(flat.size / 2)
        var i = 0
        while (i + 1 < flat.size) {
            out[flat[i]] = flat[i + 1]
            i += 2
        }
        return out
    }
}
