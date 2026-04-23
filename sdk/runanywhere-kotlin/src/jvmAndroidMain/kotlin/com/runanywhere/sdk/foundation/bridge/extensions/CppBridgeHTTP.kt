/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTP extension for CppBridge.
 * Provides HTTP transport bridge for C++ core network operations.
 *
 * Follows iOS CppBridge+HTTP.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * HTTP bridge that provides network transport callbacks for C++ core operations.
 *
 * The C++ core may need to perform HTTP requests for various operations such as:
 * - Model downloads
 * - Authentication flows
 * - Service API calls
 * - Configuration fetching
 *
 * This extension provides a unified HTTP transport layer via callbacks that C++ can invoke
 * to perform network operations using the platform's native HTTP stack.
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - HTTP requests are executed on a background thread pool
 * - Callbacks from C++ are thread-safe
 */
object CppBridgeHTTP {
    /**
     * HTTP method constants matching C++ RAC_HTTP_METHOD_* values.
     */
    object HttpMethod {
        const val GET = 0
        const val POST = 1
        const val PUT = 2
        const val DELETE = 3
        const val PATCH = 4
        const val HEAD = 5
        const val OPTIONS = 6

        /**
         * Get the string representation of an HTTP method.
         */
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

    /**
     * HTTP response status categories.
     */
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

    /**
     * HTTP error codes for C++ callback responses.
     */
    object HttpErrorCode {
        const val NONE = 0
        const val NETWORK_ERROR = 1
        const val TIMEOUT = 2
        const val INVALID_URL = 3
        const val SSL_ERROR = 4
        const val UNKNOWN = 99
    }

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeHTTP"

    /**
     * Default connection timeout in milliseconds.
     */
    private const val DEFAULT_CONNECT_TIMEOUT_MS = 30_000

    /**
     * Default read timeout in milliseconds.
     */
    private const val DEFAULT_READ_TIMEOUT_MS = 60_000

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Perform an HTTP request synchronously from Kotlin code.
     *
     * This is a utility method for performing HTTP requests from Kotlin directly,
     * not intended for use by C++ callbacks.
     *
     * @param url The request URL
     * @param method The HTTP method (see [HttpMethod] constants)
     * @param headers Map of headers to send
     * @param body Request body, or null for no body
     * @param timeoutMs Request timeout in milliseconds (0 for default)
     * @return [HttpResponse] containing status code, body, and headers
     */
    fun request(
        url: String,
        method: Int = HttpMethod.GET,
        headers: Map<String, String>? = null,
        body: String? = null,
        timeoutMs: Int = 0,
    ): HttpResponse {
        var connection: HttpURLConnection? = null

        try {
            val urlObj = URL(url)
            connection = urlObj.openConnection() as HttpURLConnection
            connection.requestMethod = HttpMethod.getName(method)

            val connectTimeout = if (timeoutMs > 0) timeoutMs else DEFAULT_CONNECT_TIMEOUT_MS
            val readTimeout = if (timeoutMs > 0) timeoutMs else DEFAULT_READ_TIMEOUT_MS
            connection.connectTimeout = connectTimeout
            connection.readTimeout = readTimeout
            connection.doInput = true

            // Set headers
            headers?.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }

            // Set default content type if not specified and body is present
            if (body != null && headers?.keys?.any { it.equals("Content-Type", ignoreCase = true) } != true) {
                connection.setRequestProperty("Content-Type", "application/json")
            }

            // Write body if present
            if (body != null && method != HttpMethod.GET && method != HttpMethod.HEAD) {
                connection.doOutput = true
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(body)
                    writer.flush()
                }
            }

            val statusCode = connection.responseCode

            val inputStream =
                if (HttpStatus.isSuccess(statusCode)) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }

            val responseBody =
                if (inputStream != null) {
                    BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8)).use { reader ->
                        reader.readText()
                    }
                } else {
                    null
                }

            val responseHeaders =
                connection.headerFields
                    .filterKeys { it != null }
                    .mapValues { it.value.firstOrNull() ?: "" }
                    .filterValues { it.isNotEmpty() }

            return HttpResponse(
                statusCode = statusCode,
                body = responseBody,
                headers = responseHeaders,
                success = HttpStatus.isSuccess(statusCode),
                errorMessage = null,
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request failed: ${e.message}",
            )
            return HttpResponse(
                statusCode = -1,
                body = null,
                headers = emptyMap(),
                success = false,
                errorMessage = e.message ?: "Unknown error",
            )
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Perform a GET request.
     */
    fun get(url: String, headers: Map<String, String>? = null, timeoutMs: Int = 0): HttpResponse {
        return request(url, HttpMethod.GET, headers, null, timeoutMs)
    }

    /**
     * Perform a POST request with JSON body.
     */
    fun post(
        url: String,
        body: String?,
        headers: Map<String, String>? = null,
        timeoutMs: Int = 0,
    ): HttpResponse {
        return request(url, HttpMethod.POST, headers, body, timeoutMs)
    }

    /**
     * Perform a PUT request with JSON body.
     */
    fun put(
        url: String,
        body: String?,
        headers: Map<String, String>? = null,
        timeoutMs: Int = 0,
    ): HttpResponse {
        return request(url, HttpMethod.PUT, headers, body, timeoutMs)
    }

    /**
     * Perform a DELETE request.
     */
    fun delete(url: String, headers: Map<String, String>? = null, timeoutMs: Int = 0): HttpResponse {
        return request(url, HttpMethod.DELETE, headers, null, timeoutMs)
    }

    /**
     * HTTP response data class.
     */
    data class HttpResponse(
        val statusCode: Int,
        val body: String?,
        val headers: Map<String, String>,
        val success: Boolean,
        val errorMessage: String?,
    )
}
