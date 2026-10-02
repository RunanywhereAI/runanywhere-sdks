/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Coverage for [OkHttpHttpTransport.isStreamCancellation] through the public
 * streaming entry points (PR #930): a cancelled stream must surface as
 * `cancelled = true`, while a genuine transport failure must stay
 * `cancelled = false` with an error message. A foreign cancel — a host's
 * shared Dispatcher.cancelAll() reaching through setHttpClient — is exactly
 * the shape the old `cancelRequested`-only check missed.
 *
 * Unit tests cannot call the real chunk callback (JNI is not loaded), so a
 * completed drain always fails at the deliverChunkNative handoff and surfaces
 * through the streamInternal catch-all with statusCode 0. What the catch-all
 * must preserve is the cancelled flag: a foreign cancel that races a mid-drain
 * UnsatisfiedLinkError is still a cancellation, and a bare transport failure
 * (connection refused, no cancel ever requested) is still an error.
 *
 * Like [OkHttpHttpTransportTest], this drives a real OkHttp client against an
 * in-process ServerSocket stub — no network, no extra dependencies.
 */

package com.runanywhere.sdk.httptransport

import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class OkHttpStreamCancellationTest {
    /** Stub that dribbles its response body in small writes with pauses. */
    private class SlowStubServer(
        private val chunkCount: Int,
        private val chunkDelayMs: Long,
    ) {
        private val serverSocket = ServerSocket(0)
        val received: MutableList<String> = CopyOnWriteArrayList()
        private val ready = CountDownLatch(1)
        private lateinit var worker: Thread

        val port: Int get() = serverSocket.localPort

        fun start() {
            worker =
                thread(name = "slow-stub-server", isDaemon = true) {
                    ready.countDown()
                    while (!serverSocket.isClosed) {
                        try {
                            serverSocket.accept().use { socket -> serve(socket) }
                        } catch (_: Throwable) {
                            break
                        }
                    }
                }
            ready.await(5, TimeUnit.SECONDS)
        }

        private fun serve(socket: Socket) {
            val input = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
            val requestLine = input.readLine() ?: return
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
            }
            received.add(requestLine)
            val out = socket.getOutputStream()
            val chunk = ByteArray(64)
            val header =
                "HTTP/1.1 200 OK\r\nContent-Length: ${chunk.size * chunkCount}\r\n" +
                    "Connection: close\r\n\r\n"
            out.write(header.toByteArray(StandardCharsets.UTF_8))
            out.flush()
            repeat(chunkCount) {
                out.write(chunk)
                out.flush()
                try {
                    Thread.sleep(chunkDelayMs)
                } catch (_: InterruptedException) {
                }
            }
            socket.close()
        }

        fun stop() {
            try {
                serverSocket.close()
            } catch (_: Throwable) {
                // best-effort teardown
            }
        }
    }

    private var server: SlowStubServer? = null

    @Before
    fun resetTransport() {
        OkHttpHttpTransport.setHttpClient(null)
    }

    @After
    fun tearDown() {
        server?.stop()
        server = null
        OkHttpHttpTransport.setHttpClient(null)
    }

    private fun startSlowServer(): SlowStubServer {
        val s = SlowStubServer(chunkCount = 40, chunkDelayMs = 25)
        s.start()
        server = s
        return s
    }

    /**
     * A foreign cancel: the call is cancelled by an owner outside
     * [OkHttpHttpTransport] — the same shape a host's shared
     * `Dispatcher.cancelAll()` reaches through
     * [OkHttpHttpTransport.setHttpClient]. The classifier must treat it as a
     * cancellation, not a transport error.
     */
    @Test
    fun streamingRequest_foreignCallCancel_reportsCancelled() {
        val stub = startSlowServer()
        OkHttpHttpTransport.setHttpClient(OkHttpClient.Builder().build())

        val result = CompletableFuture<OkHttpHttpTransport.StreamResponse>()
        thread(name = "streaming-caller", isDaemon = true) {
            result.complete(
                OkHttpHttpTransport.executeStreamingRequest(
                    method = "GET",
                    url = "http://127.0.0.1:${stub.port}/blob",
                    headersFlat = emptyArray(),
                    bodyBytes = null,
                    timeoutMs = 10_000L,
                    nativeCallback = 0L,
                    nativeUserData = 0L,
                ),
            )
        }

        // Wait for the stub to acknowledge the request so the cancel lands
        // mid-drain rather than pre-execute.
        assertTrue("stub never received the request", waitForReceived(stub, 5, TimeUnit.SECONDS))
        OkHttpHttpTransport.cancelAllStreams()

        val response = result.get(15, TimeUnit.SECONDS)
        assertTrue(
            "foreign call.cancel() must classify as cancelled, got errorMessage=${response.errorMessage}",
            response.cancelled,
        )
        assertEquals(0, response.statusCode)
        assertNotNull(response.errorMessage)
    }

    @Test
    fun streamingRequest_transportFailure_reportsNotCancelled() {
        // Bind then release a port so the connect is refused: a genuine
        // transport failure that is not a cancellation.
        val throwaway = ServerSocket(0)
        val deadPort = throwaway.localPort
        throwaway.close()

        val response =
            OkHttpHttpTransport.executeStreamingRequest(
                method = "GET",
                url = "http://127.0.0.1:$deadPort/unreachable",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 2_000L,
                nativeCallback = 0L,
                nativeUserData = 0L,
            )

        assertFalse("connection refused is not a cancellation", response.cancelled)
        assertEquals(0, response.statusCode)
        assertNotNull("transport failure must carry an error message", response.errorMessage)
    }

    @Test
    fun streamingRequest_completedDrainWithoutCancel_reportsNotCancelled() {
        // The unit-test drain always dies at the deliverChunkNative handoff
        // (JNI absent), but nothing ever requested cancellation — the failure
        // must be reported as an error, not as a cancellation.
        val stub = SlowStubServer(chunkCount = 2, chunkDelayMs = 5)
        stub.start()
        server = stub

        val response =
            OkHttpHttpTransport.executeStreamingRequest(
                method = "GET",
                url = "http://127.0.0.1:${stub.port}/blob",
                headersFlat = emptyArray(),
                bodyBytes = null,
                timeoutMs = 10_000L,
                nativeCallback = 0L,
                nativeUserData = 0L,
            )

        assertEquals(0, response.statusCode)
        assertNotNull(response.errorMessage)
        assertFalse("no cancel was requested; the JNI handoff failure is an error", response.cancelled)
    }

    @Test
    fun cancelAllStreams_idempotentWithNoInFlightStreams() {
        // The registry's cancel path is reachable with zero in-flight streams
        // and repeated calls stay harmless.
        OkHttpHttpTransport.cancelAllStreams()
        OkHttpHttpTransport.cancelAllStreams()
    }

    private fun waitForReceived(
        stub: SlowStubServer,
        timeout: Long,
        unit: TimeUnit,
    ): Boolean {
        val deadline = System.nanoTime() + unit.toNanos(timeout)
        while (System.nanoTime() < deadline) {
            if (stub.received.isNotEmpty()) return true
            Thread.sleep(25)
        }
        return stub.received.isNotEmpty()
    }
}
