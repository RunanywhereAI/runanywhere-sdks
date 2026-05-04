/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTP extension for CppBridge.
 *
 * Post T3.5: this used to be a 275 LOC HttpURLConnection wrapper. All
 * of that plumbing now lives in the commons libcurl-backed
 * `rac_http_client_*` C ABI, accessed via
 * [RunAnywhereBridge.racHttpRequestExecute]. This file retains only the
 * public helper surface (HttpMethod constants, HttpResponse record,
 * get/post/put/delete/request shorthands) that the rest of the Kotlin
 * SDK (CppBridgeModelAssignment etc.) compiles against.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Synchronous HTTP helper. Every call routes through the native curl
 * HTTP client — no Kotlin-side socket / HttpURLConnection code remains.
 */
object CppBridgeHTTP {
    private const val TAG = "CppBridgeHTTP"

    /** Default call timeout in ms applied when the caller passes 0. */
    private const val DEFAULT_TIMEOUT_MS = 60_000

    /** HTTP method ordinals — matched to `rac_http_*` method strings. */
    object HttpMethod {
        const val GET = 0
        const val POST = 1
        const val PUT = 2
        const val DELETE = 3
        const val PATCH = 4
        const val HEAD = 5
        const val OPTIONS = 6

        fun getName(method: Int): String =
            when (method) {
                GET -> "GET"
                POST -> "POST"
                PUT -> "PUT"
                DELETE -> "DELETE"
                PATCH -> "PATCH"
                HEAD -> "HEAD"
                OPTIONS -> "OPTIONS"
                else -> "GET"
            }
    }

    /** Status-code classification helpers. */
    object HttpStatus {
        const val SUCCESS_MIN = 200
        const val SUCCESS_MAX = 299
        const val REDIRECT_MIN = 300
        const val REDIRECT_MAX = 399
        const val CLIENT_ERROR_MIN = 400
        const val CLIENT_ERROR_MAX = 499
        const val SERVER_ERROR_MIN = 500
        const val SERVER_ERROR_MAX = 599

        fun isSuccess(statusCode: Int): Boolean = statusCode in SUCCESS_MIN..SUCCESS_MAX

        fun isRedirect(statusCode: Int): Boolean = statusCode in REDIRECT_MIN..REDIRECT_MAX

        fun isClientError(statusCode: Int): Boolean = statusCode in CLIENT_ERROR_MIN..CLIENT_ERROR_MAX

        fun isServerError(statusCode: Int): Boolean = statusCode in SERVER_ERROR_MIN..SERVER_ERROR_MAX

        fun isError(statusCode: Int): Boolean = isClientError(statusCode) || isServerError(statusCode)
    }

    /** Error codes kept for call-site API compatibility. */
    object HttpErrorCode {
        const val NONE = 0
        const val NETWORK_ERROR = 1
        const val TIMEOUT = 2
        const val INVALID_URL = 3
        const val SSL_ERROR = 4
        const val UNKNOWN = 99
    }

    /**
     * Perform an HTTP request via the native curl-backed client.
     *
     * @param url The request URL (absolute HTTP/HTTPS).
     * @param method One of the [HttpMethod] constants.
     * @param headers Optional header map (Content-Type defaults to application/json
     *                when a body is present and no Content-Type header was supplied).
     * @param body Optional request body — ignored for GET/HEAD.
     * @param timeoutMs Timeout in ms (0 → [DEFAULT_TIMEOUT_MS]).
     */
    fun request(
        url: String,
        method: Int = HttpMethod.GET,
        headers: Map<String, String>? = null,
        body: String? = null,
        timeoutMs: Int = 0,
    ): HttpResponse {
        val methodName = HttpMethod.getName(method)
        val effectiveTimeout = if (timeoutMs > 0) timeoutMs else DEFAULT_TIMEOUT_MS

        // Ensure Content-Type for bodied methods when caller didn't set one —
        // mirrors the legacy HttpURLConnection behaviour.
        val resolved =
            if (body != null &&
                method != HttpMethod.GET &&
                method != HttpMethod.HEAD &&
                headers?.keys?.any { it.equals("Content-Type", ignoreCase = true) } != true
            ) {
                (headers ?: emptyMap()) + ("Content-Type" to "application/json")
            } else {
                headers ?: emptyMap()
            }

        val keys = resolved.keys.toTypedArray()
        val values = resolved.values.toTypedArray()
        val bodyBytes: ByteArray? =
            if (body != null && method != HttpMethod.GET && method != HttpMethod.HEAD) {
                body.encodeToByteArray()
            } else {
                null
            }

        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
                method = methodName,
                url = url,
                headerKeys = keys,
                headerValues = values,
                body = bodyBytes,
                timeoutMs = effectiveTimeout,
                followRedirects = true,
            )

        if (resp == null || resp.errorMessage != null) {
            val err = resp?.errorMessage ?: "native HTTP call returned null"
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request failed: $err",
            )
            return HttpResponse(
                statusCode = resp?.statusCode ?: -1,
                body = null,
                headers = emptyMap(),
                success = false,
                errorMessage = err,
            )
        }

        return HttpResponse(
            statusCode = resp.statusCode,
            body = resp.bodyAsString().ifEmpty { null },
            headers = resp.headersAsMap(),
            success = HttpStatus.isSuccess(resp.statusCode),
            errorMessage = null,
        )
    }

    /** Perform a GET request. */
    fun get(url: String, headers: Map<String, String>? = null, timeoutMs: Int = 0): HttpResponse =
        request(url, HttpMethod.GET, headers, null, timeoutMs)

    /** Perform a POST request with an optional body. */
    fun post(
        url: String,
        body: String?,
        headers: Map<String, String>? = null,
        timeoutMs: Int = 0,
    ): HttpResponse = request(url, HttpMethod.POST, headers, body, timeoutMs)

    /** Perform a PUT request with an optional body. */
    fun put(
        url: String,
        body: String?,
        headers: Map<String, String>? = null,
        timeoutMs: Int = 0,
    ): HttpResponse = request(url, HttpMethod.PUT, headers, body, timeoutMs)

    /** Perform a DELETE request. */
    fun delete(url: String, headers: Map<String, String>? = null, timeoutMs: Int = 0): HttpResponse =
        request(url, HttpMethod.DELETE, headers, null, timeoutMs)

    /**
     * HTTP response record.
     *
     * [body] is the UTF-8 decoded body, or null when the server sent an
     * empty body. [headers] is a deduplicated flat string map; when the
     * server sent multiple values for the same header only the first is
     * preserved (matches the pre-T3.5 HttpURLConnection behaviour).
     */
    data class HttpResponse(
        val statusCode: Int,
        val body: String?,
        val headers: Map<String, String>,
        val success: Boolean,
        val errorMessage: String?,
    )
}
