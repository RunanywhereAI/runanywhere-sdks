/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform HTTP transport adapter — Flutter plugin copy.
 *
 * This is a copy of the Kotlin SDK's file at
 *   sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/http/OkHttpTransport.kt
 *
 * Why duplicate? The Flutter plugin does NOT depend on the Kotlin SDK module —
 * it loads `librunanywhere_jni.so` directly. The prebuilt JNI bridge resolves
 * JNI symbols against the fully-qualified Java class name
 *   Java_com_runanywhere_sdk_foundation_http_OkHttpTransport_deliverChunkNative
 * so this class MUST live at the exact same package+name.
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
 */

package com.runanywhere.sdk.foundation.http

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Platform HTTP transport adapter. C++ core calls into this class via JNI when
 * the OkHttp transport is registered. OkHttp gives us the system CA store,
 * proxies, NetworkSecurityConfig, HTTP/2, cert pinning, user-CAs for free.
 */
object OkHttpTransport {
    /** Chunk size used for streaming body delivery (32 KB matches Okio's default). */
    private const val STREAM_CHUNK_SIZE = 32 * 1024

    /** Default OkHttp client. Lazily built on first use. */
    private val defaultClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    /**
     * Active client reference. App teams can swap this via [setHttpClient] to
     * plug in their own interceptors (OkHttp Logging, Chucker), custom cert
     * pinners, DNS resolvers, or a WorkManager-friendly variant with longer
     * timeouts.
     *
     * Reads are lock-free (AtomicReference); writes are atomic.
     */
    private val clientRef: AtomicReference<OkHttpClient?> = AtomicReference(null)

    /** Resolve the currently configured client, falling back to the default. */
    private fun activeClient(): OkHttpClient = clientRef.get() ?: defaultClient

    /**
     * Install a custom [OkHttpClient]. This is the standard Android escape
     * hatch for apps that need to attach interceptors, custom SSL contexts,
     * Chucker, certificate pinners, or longer timeouts for WorkManager
     * downloads.
     *
     * Safe to call at any time; subsequent requests pick up the new client.
     * Pass `null` to fall back to the default client.
     */
    @JvmStatic
    fun setHttpClient(client: OkHttpClient?) {
        clientRef.set(client)
    }

    /** Returns the currently installed custom client, or null if using default. */
    @JvmStatic
    fun getHttpClient(): OkHttpClient? = clientRef.get()

    /**
     * Synchronous request entry point. Invoked from JNI via
     * `CallStaticObjectMethod`. Returns a [HttpResponse] — C++ unwraps the
     * fields and marshals them into `rac_http_response_t`.
     */
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

    /**
     * Streaming request entry point. Each chunk OkHttp reads off the wire is
     * handed back via a native callback — the C++ side translates the
     * `long nativeHandle` into the real `rac_http_body_chunk_fn` and forwards
     * the bytes. Cancellation: when the native side signals "stop" by
     * returning `false` from `deliverChunkNative`, we call [okhttp3.Call.cancel]
     * to abort the TCP connection.
     */
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

    /**
     * Native bridge: hands a chunk to the C `rac_http_body_chunk_fn` pointed
     * to by [nativeCallback]. Implemented in the bundled `librunanywhere_jni.so`
     * (from commons). Returns `false` when the native side wants to cancel.
     */
    @JvmStatic
    private external fun deliverChunkNative(
        nativeCallback: Long,
        nativeUserData: Long,
        chunk: ByteArray,
        chunkLen: Int,
        totalWritten: Long,
        contentLength: Long,
    ): Boolean

    // -------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------

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
        val base = activeClient()
        return if (timeoutMs > 0) {
            base.newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .build()
        } else {
            base
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

    /**
     * Response DTO for the blocking path. Layout matches the JNI
     * FindClass/GetFieldID lookups in `okhttp_transport_adapter.cpp` (baked
     * into librunanywhere_jni.so) — do NOT rename fields.
     */
    class HttpResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val bodyBytes: ByteArray,
        @JvmField val errorMessage: String?,
    )

    /**
     * Response DTO for the streaming path. Body is delivered chunk-by-chunk
     * through [deliverChunkNative]; this struct only carries status + headers
     * metadata back to C++ for the `rac_http_response_t`.
     */
    class StreamResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val errorMessage: String?,
        @JvmField val cancelled: Boolean,
    )

    /** Empty body used for bodied verbs called without a payload. */
    private val EMPTY_BODY: RequestBody = ByteArray(0).toRequestBody()
}
