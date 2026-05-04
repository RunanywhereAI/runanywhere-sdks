/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform HTTP transport adapter — React Native copy (v2 close-out Phase H6 + R3).
 *
 * This is a NEAR-DUPLICATE of the Kotlin SDK's file at
 *   sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/http/OkHttpTransport.kt
 *
 * Why duplicate? React Native Android does NOT depend on the Kotlin SDK —
 * it loads `librac_commons.so` directly via its own `librunanywherecore.so`
 * shim. Therefore the JNI adapter (okhttp_transport_adapter.cpp) compiled
 * into `librunanywherecore.so` needs to find a Kotlin class at the SAME
 * package + class name the adapter greps for via FindClass. The simplest
 * way to keep both SDKs working in the same app is to keep the package
 * path identical on both sides.
 *
 * If both packages appear on the same classpath (e.g. an Android app that
 * imports BOTH runanywhere-kotlin and the RN core), Gradle will reject the
 * duplicate. Consumers are expected to pick one integration path.
 *
 * The C++ core holds a `rac_http_transport_ops` vtable registered via
 * `rac_http_transport_register`. When that vtable is non-null, every
 * `rac_http_request_*` call is routed to the adapter instead of libcurl.
 *
 * Why OkHttp? The libcurl default is portable but uses its own TLS /
 * CA-bundle story. On Android, routing through OkHttp gives us the
 * system trust store + user-CAs + NetworkSecurityConfig + proxy + HTTP/2
 * + cert pinning for free, which in turn fixes the rc=77 SSL failure
 * seen on ~5% of corporate / user-rooted devices.
 *
 * Threading: OkHttp is thread-safe; the singleton client is reused.
 * Each execute* call blocks the caller thread — native JNI code
 * is expected to run these off the main thread.
 *
 * R3 additions:
 *   - Real streaming via ResponseBody.source(), chunked delivery
 *   - Cancellation via Call.cancel() when onChunk returns false
 */

package com.runanywhere.sdk.foundation.http

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Platform HTTP transport adapter. C++ core calls into this class via JNI when
 * the OkHttp transport is registered. OkHttp gives us the system CA store,
 * proxies, NetworkSecurityConfig, HTTP/2, cert pinning, user-CAs for free.
 */
object OkHttpTransport {
    private const val STREAM_CHUNK_SIZE = 32 * 1024

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    @JvmStatic
    fun executeRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
    ): HttpResponse {
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes)
            val clientForCall = resolveClient(timeoutMs)

            clientForCall.newCall(request).execute().use { resp ->
                val headerPairs = flattenHeaders(resp.headers)
                val responseBody = resp.body?.bytes() ?: ByteArray(0)
                HttpResponse(
                    statusCode = resp.code,
                    headers = headerPairs,
                    bodyBytes = responseBody,
                    errorMessage = null,
                )
            }
        } catch (e: Throwable) {
            HttpResponse(
                statusCode = 0,
                headers = emptyArray(),
                bodyBytes = ByteArray(0),
                errorMessage = "${e.javaClass.simpleName}: ${e.message ?: "unknown"}",
            )
        }
    }

    @JvmStatic
    fun executeStreamingRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
        nativeCallback: Long,
        nativeUserData: Long,
    ): StreamResponse {
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes)
            val clientForCall = resolveClient(timeoutMs)

            val call = clientForCall.newCall(request)
            call.execute().use { resp ->
                val headerPairs = flattenHeaders(resp.headers)
                val body = resp.body
                    ?: return StreamResponse(
                        statusCode = resp.code,
                        headers = headerPairs,
                        errorMessage = null,
                        cancelled = false,
                    )

                val contentLength = if (body.contentLength() >= 0) body.contentLength() else 0L
                val buffer = ByteArray(STREAM_CHUNK_SIZE)
                var totalRead = 0L
                var cancelled = false

                body.byteStream().use { input ->
                    while (true) {
                        val n = try {
                            input.read(buffer)
                        } catch (io: IOException) {
                            if (call.isCanceled()) {
                                cancelled = true
                                break
                            }
                            throw io
                        }
                        if (n < 0) break
                        if (n == 0) continue

                        totalRead += n
                        val chunk = if (n == buffer.size) buffer else buffer.copyOf(n)
                        val keepGoing = deliverChunkNative(
                            nativeCallback, nativeUserData,
                            chunk, n, totalRead, contentLength,
                        )
                        if (!keepGoing) {
                            cancelled = true
                            call.cancel()
                            break
                        }
                    }
                }

                StreamResponse(
                    statusCode = resp.code,
                    headers = headerPairs,
                    errorMessage = null,
                    cancelled = cancelled,
                )
            }
        } catch (e: Throwable) {
            StreamResponse(
                statusCode = 0,
                headers = emptyArray(),
                errorMessage = "${e.javaClass.simpleName}: ${e.message ?: "unknown"}",
                cancelled = false,
            )
        }
    }

    @JvmStatic
    private external fun deliverChunkNative(
        nativeCallback: Long,
        nativeUserData: Long,
        chunk: ByteArray,
        chunkLen: Int,
        totalWritten: Long,
        contentLength: Long,
    ): Boolean

    private fun buildRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
    ): Request {
        val builder = Request.Builder().url(url)

        var contentType: String? = null
        var i = 0
        while (i < headersFlat.size - 1) {
            val name = headersFlat[i]
            val value = headersFlat[i + 1]
            builder.addHeader(name, value)
            if (name.equals("Content-Type", ignoreCase = true)) {
                contentType = value
            }
            i += 2
        }

        val body: RequestBody? =
            bodyBytes?.toRequestBody(
                contentType = contentType?.toMediaTypeOrNull(),
            )

        when (method.uppercase()) {
            "GET" -> builder.get()
            "POST" -> builder.post(body ?: EMPTY_BODY)
            "PUT" -> builder.put(body ?: EMPTY_BODY)
            "DELETE" -> if (body != null) builder.delete(body) else builder.delete()
            "PATCH" -> builder.patch(body ?: EMPTY_BODY)
            "HEAD" -> builder.head()
            else -> builder.method(method, body)
        }

        return builder.build()
    }

    private fun resolveClient(timeoutMs: Long): OkHttpClient {
        return if (timeoutMs > 0) {
            client.newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .build()
        } else {
            client
        }
    }

    private fun flattenHeaders(headers: okhttp3.Headers): Array<String> {
        val pairs = ArrayList<String>(headers.size * 2)
        for ((name, value) in headers) {
            pairs.add(name)
            pairs.add(value)
        }
        return pairs.toTypedArray()
    }

    class HttpResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val bodyBytes: ByteArray,
        @JvmField val errorMessage: String?,
    )

    class StreamResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val errorMessage: String?,
        @JvmField val cancelled: Boolean,
    )

    private val EMPTY_BODY: RequestBody = ByteArray(0).toRequestBody()
}
