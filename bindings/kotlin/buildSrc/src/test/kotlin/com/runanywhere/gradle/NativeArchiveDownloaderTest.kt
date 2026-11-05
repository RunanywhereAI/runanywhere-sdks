package com.runanywhere.gradle

import com.sun.net.httpserver.HttpServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets

class NativeArchiveDownloaderTest {
    private var server: HttpServer? = null

    @AfterEach
    fun tearDown() {
        server?.stop(0)
        server = null
    }

    @Test
    fun `writes a 200 response body to the destination file`() {
        val body = "native-archive-bytes"
        val port = startServer { exchange ->
            val response = body.toByteArray(StandardCharsets.UTF_8)
            exchange.sendResponseHeaders(200, response.size.toLong())
            exchange.responseBody.use { it.write(response) }
        }
        val dest = File.createTempFile("jni-", ".zip")
        try {
            NativeArchiveDownloader.downloadWithTimeouts("http://127.0.0.1:$port/archive.zip", dest)
            assertEquals(body, dest.readText())
        } finally {
            dest.delete()
        }
    }

    @Test
    fun `4xx fails fast without leaving a partial file`() {
        val port = startServer { exchange ->
            exchange.sendResponseHeaders(404, -1)
            exchange.responseBody.close()
        }
        val dest = File.createTempFile("jni-", ".zip")
        dest.writeText("stale")
        try {
            assertThrows(NonRetryableDownloadException::class.java) {
                NativeArchiveDownloader.downloadWithTimeouts("http://127.0.0.1:$port/missing.zip", dest)
            }
            assertFalse(dest.exists(), "partial download must be deleted on 4xx")
        } finally {
            dest.delete()
        }
    }

    @Test
    fun `retries transient 5xx then succeeds`() {
        var attempts = 0
        val body = "ok"
        val port = startServer { exchange ->
            attempts += 1
            if (attempts < 2) {
                exchange.sendResponseHeaders(503, -1)
                exchange.responseBody.close()
                return@startServer
            }
            val response = body.toByteArray(StandardCharsets.UTF_8)
            exchange.sendResponseHeaders(200, response.size.toLong())
            exchange.responseBody.use { it.write(response) }
        }
        val dest = File.createTempFile("jni-", ".zip")
        try {
            NativeArchiveDownloader.downloadWithTimeouts("http://127.0.0.1:$port/flaky.zip", dest)
            assertTrue(attempts >= 2)
            assertEquals(body, dest.readText())
        } finally {
            dest.delete()
        }
    }

    private fun startServer(handler: (com.sun.net.httpserver.HttpExchange) -> Unit): Int {
        val httpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        httpServer.createContext("/") { exchange -> handler(exchange) }
        httpServer.start()
        server = httpServer
        return httpServer.address.port
    }
}
