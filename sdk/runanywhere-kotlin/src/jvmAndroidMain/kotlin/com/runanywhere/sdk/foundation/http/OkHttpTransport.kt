/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform HTTP transport adapter (v2 close-out Phase H4).
 *
 * The C++ core holds a `rac_http_transport_ops` vtable registered via
 * `rac_http_transport_register`. When that vtable is non-null, every
 * `rac_http_request_*` call is routed to the adapter instead of libcurl.
 *
 * This class is the Kotlin side of the adapter. A thin C++ JNI wrapper
 * (okhttp_transport_adapter.cpp) implements the vtable and calls
 * [OkHttpTransport.executeRequest] via reflection when requests arrive.
 *
 * Why OkHttp? The libcurl default is portable but uses its own TLS /
 * CA-bundle story. On Android, routing through OkHttp gives us the
 * system trust store + user-CAs + NetworkSecurityConfig + proxy + HTTP/2
 * + cert pinning for free, which in turn fixes the rc=77 SSL failure
 * seen on ~5% of corporate / user-rooted devices.
 *
 * Threading: OkHttp is thread-safe; the singleton client is reused.
 * Each executeRequest call blocks the caller thread — native JNI code
 * is expected to run these off the main thread.
 */

package com.runanywhere.sdk.foundation.http

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Platform HTTP transport adapter. C++ core calls into this class via JNI when
 * the OkHttp transport is registered. OkHttp gives us the system CA store,
 * proxies, NetworkSecurityConfig, HTTP/2, cert pinning, user-CAs for free.
 */
object OkHttpTransport {
    /**
     * Shared OkHttp client. Reused across all requests to benefit from
     * connection pooling, HTTP/2 multiplexing, and a single TLS session cache.
     */
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    /**
     * Synchronous request entry point. Invoked from JNI via
     * `CallStaticObjectMethod`. Returns a [HttpResponse] — C++ unwraps the
     * fields and marshals them into `rac_http_response_t`.
     *
     * @param method HTTP method in uppercase ASCII ("GET"/"POST"/...).
     * @param url Absolute HTTP/HTTPS URL.
     * @param headersFlat Flat `[k1, v1, k2, v2, ...]` header array
     *                    (matches the shape of `rac_http_header_kv_t[]`).
     * @param bodyBytes Request body bytes, or null for GET/HEAD.
     * @param timeoutMs Call timeout in ms (0 = use the shared client defaults).
     * @return [HttpResponse]. On transport failure `statusCode == 0` and
     *         [HttpResponse.errorMessage] is non-null.
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
            val builder = Request.Builder().url(url)

            // Collect Content-Type for body media-type resolution before
            // we attach headers to OkHttp's builder.
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

            val clientForCall =
                if (timeoutMs > 0) {
                    client.newBuilder()
                        .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                        .build()
                } else {
                    client
                }

            clientForCall.newCall(builder.build()).execute().use { resp ->
                val headerPairs = ArrayList<String>(resp.headers.size * 2)
                for ((name, value) in resp.headers) {
                    headerPairs.add(name)
                    headerPairs.add(value)
                }
                val responseBody = resp.body?.bytes() ?: ByteArray(0)
                HttpResponse(
                    statusCode = resp.code,
                    headers = headerPairs.toTypedArray(),
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
     * Response DTO. Layout matches the JNI FindClass/GetFieldID lookups in
     * `okhttp_transport_adapter.cpp` — do NOT rename fields without updating
     * the C++ side.
     */
    class HttpResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val bodyBytes: ByteArray,
        @JvmField val errorMessage: String?,
    )

    /** Empty body used for bodied verbs called without a payload. */
    private val EMPTY_BODY: RequestBody = ByteArray(0).toRequestBody()
}
