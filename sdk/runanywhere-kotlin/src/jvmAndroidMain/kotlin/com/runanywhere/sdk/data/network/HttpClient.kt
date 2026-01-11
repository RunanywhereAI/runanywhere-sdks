package com.runanywhere.sdk.data.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * JVM implementation of HttpClient using HttpURLConnection.
 */
class JvmHttpClient(
    private val config: NetworkConfiguration = NetworkConfiguration(),
) : HttpClient {
    private var defaultTimeout: Long = config.connectTimeoutMs
    private var defaultHeaders: Map<String, String> = emptyMap()

    override suspend fun get(
        url: String,
        headers: Map<String, String>,
    ): HttpResponse =
        withContext(Dispatchers.IO) {
            executeRequest(url, "GET", headers, null)
        }

    override suspend fun post(
        url: String,
        body: ByteArray,
        headers: Map<String, String>,
    ): HttpResponse =
        withContext(Dispatchers.IO) {
            executeRequest(url, "POST", headers, body)
        }

    override suspend fun put(
        url: String,
        body: ByteArray,
        headers: Map<String, String>,
    ): HttpResponse =
        withContext(Dispatchers.IO) {
            executeRequest(url, "PUT", headers, body)
        }

    override suspend fun delete(
        url: String,
        headers: Map<String, String>,
    ): HttpResponse =
        withContext(Dispatchers.IO) {
            executeRequest(url, "DELETE", headers, null)
        }

    override suspend fun download(
        url: String,
        headers: Map<String, String>,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?,
    ): ByteArray =
        withContext(Dispatchers.IO) {
            val connection =
                (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = defaultTimeout.toInt()
                    readTimeout = defaultTimeout.toInt()
                    defaultHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
                    headers.forEach { (k, v) -> setRequestProperty(k, v) }
                }

            try {
                val totalBytes = connection.contentLengthLong
                val buffer = ByteArray(8192)
                val output = ByteArrayOutputStream()
                var bytesDownloaded = 0L

                connection.inputStream.use { input ->
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        bytesDownloaded += bytesRead
                        onProgress?.invoke(bytesDownloaded, totalBytes)
                    }
                }

                output.toByteArray()
            } finally {
                connection.disconnect()
            }
        }

    override suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?,
    ): HttpResponse =
        withContext(Dispatchers.IO) {
            val connection =
                (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = defaultTimeout.toInt()
                    readTimeout = defaultTimeout.toInt()
                    defaultHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
                    headers.forEach { (k, v) -> setRequestProperty(k, v) }
                    setFixedLengthStreamingMode(data.size)
                }

            try {
                connection.outputStream.use { output ->
                    var bytesUploaded = 0L
                    val chunkSize = 8192
                    var offset = 0
                    while (offset < data.size) {
                        val length = minOf(chunkSize, data.size - offset)
                        output.write(data, offset, length)
                        bytesUploaded += length
                        offset += length
                        onProgress?.invoke(bytesUploaded, data.size.toLong())
                    }
                    output.flush()
                }

                val responseBody = connection.inputStream.use { it.readBytes() }
                val responseHeaders =
                    connection.headerFields
                        .filterKeys { it != null }
                        .mapKeys { it.key!! }

                HttpResponse(
                    statusCode = connection.responseCode,
                    body = responseBody,
                    headers = responseHeaders,
                )
            } finally {
                connection.disconnect()
            }
        }

    override fun setDefaultTimeout(timeoutMillis: Long) {
        defaultTimeout = timeoutMillis
    }

    override fun setDefaultHeaders(headers: Map<String, String>) {
        defaultHeaders = headers
    }

    private fun executeRequest(
        url: String,
        method: String,
        headers: Map<String, String>,
        body: ByteArray?,
    ): HttpResponse {
        val connection =
            (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = defaultTimeout.toInt()
                readTimeout = defaultTimeout.toInt()
                doOutput = body != null
                defaultHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
                headers.forEach { (k, v) -> setRequestProperty(k, v) }
            }

        try {
            body?.let { data ->
                connection.outputStream.use { it.write(data) }
            }

            val responseCode = connection.responseCode
            val responseBody =
                try {
                    if (responseCode in 200..299) {
                        connection.inputStream.use { it.readBytes() }
                    } else {
                        connection.errorStream?.use { it.readBytes() } ?: ByteArray(0)
                    }
                } catch (e: Exception) {
                    ByteArray(0)
                }

            val responseHeaders =
                connection.headerFields
                    .filterKeys { it != null }
                    .mapKeys { it.key!! }

            return HttpResponse(
                statusCode = responseCode,
                body = responseBody,
                headers = responseHeaders,
            )
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * JVM actual implementation for creating HttpClient.
 */
actual fun createHttpClient(): HttpClient = JvmHttpClient()

/**
 * JVM actual implementation for creating HttpClient with configuration.
 */
actual fun createHttpClient(config: NetworkConfiguration): HttpClient = JvmHttpClient(config)
