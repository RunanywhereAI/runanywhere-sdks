/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Round-trip coverage for the OkHttp-backed HTTP transport adapter
 * (`OkHttpHttpTransport`), the Kotlin parity of Swift's
 * `URLSessionHttpTransport`. Exercises the real OkHttp client end-to-end
 * against an in-process HTTP/1.1 stub built on a plain `ServerSocket`, so the
 * suite asserts wire behaviour with zero extra dependencies and no network.
 *
 * Why a hand-rolled stub instead of MockWebServer: from OkHttp 5.x,
 * MockWebServer ships as a separate `mockwebserver3` artifact (no longer a
 * transitive dependency of `okhttp`). A raw `ServerSocket` keeps the test
 * offline-buildable on the same classpath the SDK already pulls.
 *
 * Scope: the `request_send` slot ([OkHttpHttpTransport.executeRequest]) is
 * pure OkHttp and is verified for status / header / body fidelity plus the
 * transport-failure contract (statusCode == 0, non-null errorMessage). The
 * `request_resume` slot's `Range: bytes=N-` header construction is verified by
 * capturing the request the server actually receives — OkHttp transmits it
 * during `Call.execute()`, before the streaming path reaches the JNI chunk
 * callback (which is unavailable in a pure-JVM unit test). The streaming chunk
 * delivery itself is covered by the C++ JNI ctest + the cross-SDK streaming
 * parity fixtures, not here.
 */

package com.runanywhere.sdk.httptransport

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class OkHttpHttpTransportTest {
    /** A single HTTP exchange captured by the stub server. */
    private class CapturedRequest(
        val requestLine: String,
        val headers: Map<String, String>,
        val body: String,
    )

    /** Canned response the stub returns for the next request. */
    private class StubResponse(
        val statusLine: String,
        val headers: List<Pair<String, String>>,
        val body: ByteArray,
    )

    /**
     * Minimal blocking HTTP/1.1 stub. Serves exactly `responses.size` requests,
     * one per accepted connection, recording each request for assertions.
     */
    private class StubServer(
        private val responses: List<StubResponse>,
    ) {
        private val serverSocket = ServerSocket(0)
        val received: MutableList<CapturedRequest> = CopyOnWriteArrayList()
        private val ready = CountDownLatch(1)
        private lateinit var worker: Thread

        val port: Int get() = serverSocket.localPort

        fun start() {
            worker =
                thread(name = "stub-http-server", isDaemon = true) {
                    ready.countDown()
                    for (response in responses) {
                        try {
                            serverSocket.accept().use { socket -> handle(socket, response) }
                        } catch (_: Throwable) {
                            break
                        }
                    }
                }
            ready.await(5, TimeUnit.SECONDS)
        }

        private fun handle(
            socket: Socket,
            response: StubResponse,
        ) {
            val input = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
            val requestLine = input.readLine() ?: return
            val headers = LinkedHashMap<String, String>()
            var contentLength = 0
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
                val idx = line.indexOf(':')
                if (idx > 0) {
                    val name = line.substring(0, idx).trim()
                    val value = line.substring(idx + 1).trim()
                    headers[name] = value
                    if (name.equals("Content-Length", ignoreCase = true)) {
                        contentLength = value.toIntOrNull() ?: 0
                    }
                }
            }
            val bodyChars = CharArray(contentLength)
            var read = 0
            while (read < contentLength) {
                val n = input.read(bodyChars, read, contentLength - read)
                if (n < 0) break
                read += n
            }
            received.add(CapturedRequest(requestLine, headers, String(bodyChars, 0, read)))

            val out = socket.getOutputStream()
            val header = StringBuilder()
            header.append(response.statusLine).append("\r\n")
            header.append("Content-Length: ").append(response.body.size).append("\r\n")
            for ((name, value) in response.headers) {
                header
                    .append(name)
                    .append(": ")
                    .append(value)
                    .append("\r\n")
            }
            header.append("Connection: close\r\n\r\n")
            out.write(header.toString().toByteArray(StandardCharsets.UTF_8))
            out.write(response.body)
            out.flush()
        }

        fun stop() {
            try {
                serverSocket.close()
            } catch (_: Throwable) {
                // best-effort teardown
            }
        }
    }

    private var server: StubServer? = null

    @Before
    fun resetTransport() {
        // Ensure no host-installed client leaks between tests.
        OkHttpHttpTransport.setHttpClient(null)
    }

    @After
    fun tearDown() {
        server?.stop()
        server = null
        OkHttpHttpTransport.setHttpClient(null)
    }

    private fun startStub(vararg responses: StubResponse): StubServer {
        val s = StubServer(responses.toList())
        s.start()
        server = s
        return s
    }

    private fun urlFor(s: StubServer): String = "http://127.0.0.1:${s.port}/probe"

    /** Empty 200 response used by the header-only assertions below. */
    private fun okResponse(): StubResponse =
        StubResponse(statusLine = "HTTP/1.1 200 OK", headers = emptyList(), body = ByteArray(0))

    @Test
    fun executeRequest_get_returnsStatusHeadersAndBody() {
        val payload = "hello-from-stub".toByteArray(StandardCharsets.UTF_8)
        val stub =
            startStub(
                StubResponse(
                    statusLine = "HTTP/1.1 200 OK",
                    headers = listOf("Content-Type" to "text/plain", "X-Probe" to "value-1"),
                    body = payload,
                ),
            )

        val response =
            OkHttpHttpTransport.executeRequest(
                method = "GET",
                url = urlFor(stub),
                headersFlat = arrayOf("Accept", "text/plain"),
                bodyBytes = null,
                timeoutMs = 5_000L,
            )

        assertEquals(200, response.statusCode)
        assertNull(response.errorMessage)
        assertEquals("hello-from-stub", String(response.bodyBytes, StandardCharsets.UTF_8))

        val flat = response.headers.toList()
        assertTrue("expected X-Probe header echoed back, got $flat", flat.contains("value-1"))

        val captured = stub.received.single()
        assertTrue(captured.requestLine.startsWith("GET /probe"))
        assertEquals("text/plain", captured.headers["Accept"])
    }

    @Test
    fun executeRequest_post_sendsBodyAndContentType() {
        val stub =
            startStub(
                StubResponse(
                    statusLine = "HTTP/1.1 201 Created",
                    headers = listOf("Content-Type" to "application/json"),
                    body = "{\"ok\":true}".toByteArray(StandardCharsets.UTF_8),
                ),
            )

        val body = "{\"name\":\"value\"}".toByteArray(StandardCharsets.UTF_8)
        val response =
            OkHttpHttpTransport.executeRequest(
                method = "POST",
                url = urlFor(stub),
                headersFlat = arrayOf("Content-Type", "application/json"),
                bodyBytes = body,
                timeoutMs = 5_000L,
            )

        assertEquals(201, response.statusCode)
        assertNull(response.errorMessage)

        val captured = stub.received.single()
        assertTrue(captured.requestLine.startsWith("POST /probe"))
        assertEquals("{\"name\":\"value\"}", captured.body)
        assertEquals("application/json", captured.headers["Content-Type"])
    }

    @Test
    fun executeRequest_transportFailure_reportsZeroStatusAndError() {
        // Bind then immediately release a port so the connect attempt is refused.
        val throwaway = ServerSocket(0)
        val deadPort = throwaway.localPort
        throwaway.close()

        val response =
            OkHttpHttpTransport.executeRequest(
                method = "GET",
                url = "http://127.0.0.1:$deadPort/unreachable",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 2_000L,
            )

        assertEquals(0, response.statusCode)
        assertNotNull("transport failure must surface an error message", response.errorMessage)
        assertEquals(0, response.bodyBytes.size)
    }

    @Test
    fun executeRequest_noRedirect_returnsOriginalResponseAndProtectsDestination() {
        val destination = StubServer(listOf(okResponse())).also { it.start() }
        val redirect =
            StubServer(
                listOf(
                    StubResponse(
                        statusLine = "HTTP/1.1 307 Temporary Redirect",
                        headers = listOf("Location" to urlFor(destination)),
                        body = ByteArray(0),
                    ),
                ),
            ).also { it.start() }
        try {
            val response =
                OkHttpHttpTransport.executeRequest(
                    method = "POST",
                    url = urlFor(redirect),
                    headersFlat = arrayOf("apikey", "mobile-public-key"),
                    bodyBytes = "device-registration".toByteArray(StandardCharsets.UTF_8),
                    timeoutMs = 5_000L,
                    followRedirects = false,
                )

            assertEquals(307, response.statusCode)
            assertEquals(1, redirect.received.size)
            assertTrue("redirect destination must not receive credentials or body", destination.received.isEmpty())
        } finally {
            redirect.stop()
            destination.stop()
        }
    }

    @Test
    fun executeResumeRequest_attachesRangeHeader() {
        // The streaming/resume path delivers the body through a native JNI
        // callback that is absent in a pure-JVM test, so the call ultimately
        // fails after the response is read. The assertion of record is the
        // request the server receives: OkHttp transmits the `Range` header
        // during Call.execute(), well before the chunk callback is reached.
        val stub =
            startStub(
                StubResponse(
                    statusLine = "HTTP/1.1 206 Partial Content",
                    headers = listOf("Content-Range" to "bytes 1024-2047/4096"),
                    body = ByteArray(8) { it.toByte() },
                ),
            )

        OkHttpHttpTransport.executeResumeRequest(
            method = "GET",
            url = urlFor(stub),
            headersFlat = emptyArray(),
            bodyBytes = null,
            timeoutMs = 5_000L,
            resumeFromByte = 1024L,
            nativeCallback = 0L,
            nativeUserData = 0L,
        )

        val captured = stub.received.single()
        assertEquals("bytes=1024-", captured.headers["Range"])
    }

    @Test
    fun executeRequest_noRangeHeaderWhenNotResuming() {
        val stub =
            startStub(
                StubResponse(
                    statusLine = "HTTP/1.1 200 OK",
                    headers = emptyList(),
                    body = ByteArray(0),
                ),
            )

        OkHttpHttpTransport.executeRequest(
            method = "GET",
            url = urlFor(stub),
            headersFlat = emptyArray(),
            bodyBytes = null,
            timeoutMs = 5_000L,
        )

        val captured = stub.received.single()
        assertNull("non-resume requests must not carry a Range header", captured.headers["Range"])
    }
}
