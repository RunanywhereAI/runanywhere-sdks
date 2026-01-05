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
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

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
        fun getName(method: Int): String = when (method) {
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

    @Volatile
    private var isRegistered: Boolean = false

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

    /**
     * Maximum response size in bytes (10 MB).
     */
    private const val MAX_RESPONSE_SIZE = 10 * 1024 * 1024

    /**
     * Background executor for HTTP requests.
     * Using a cached thread pool to handle concurrent HTTP requests efficiently.
     */
    private val httpExecutor = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "runanywhere-http").apply {
            isDaemon = true
        }
    }

    /**
     * Optional interceptor for customizing HTTP requests.
     * Set this before calling [register] to customize requests (e.g., add auth headers).
     */
    @Volatile
    var requestInterceptor: HttpRequestInterceptor? = null

    /**
     * Optional listener for HTTP request events.
     * Set this to receive notifications about HTTP operations.
     */
    @Volatile
    var requestListener: HttpRequestListener? = null

    /**
     * Interface for intercepting and modifying HTTP requests.
     */
    interface HttpRequestInterceptor {
        /**
         * Called before an HTTP request is sent.
         * Can be used to add headers, modify the URL, etc.
         *
         * @param url The request URL
         * @param method The HTTP method (see [HttpMethod] constants)
         * @param headers Mutable map of headers to be sent with the request
         * @return Modified URL, or the original URL if no changes needed
         */
        fun onBeforeRequest(url: String, method: Int, headers: MutableMap<String, String>): String
    }

    /**
     * Listener interface for HTTP request events.
     */
    interface HttpRequestListener {
        /**
         * Called when an HTTP request starts.
         *
         * @param requestId Unique identifier for this request
         * @param url The request URL
         * @param method The HTTP method
         */
        fun onRequestStart(requestId: String, url: String, method: Int)

        /**
         * Called when an HTTP request completes.
         *
         * @param requestId Unique identifier for this request
         * @param statusCode The HTTP status code (-1 if request failed before getting a response)
         * @param success Whether the request was successful
         * @param durationMs Request duration in milliseconds
         * @param errorMessage Error message if the request failed, null otherwise
         */
        fun onRequestComplete(
            requestId: String,
            statusCode: Int,
            success: Boolean,
            durationMs: Long,
            errorMessage: String?
        )
    }

    /**
     * Register the HTTP callback with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register the HTTP callback with C++ via JNI
            // The callback will be invoked by C++ when HTTP requests need to be made
            // TODO: Call native registration
            // nativeSetHttpCallback()

            isRegistered = true
        }
    }

    /**
     * Check if the HTTP callback is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // HTTP CALLBACK
    // ========================================================================

    /**
     * HTTP callback invoked by C++ core to perform HTTP requests.
     *
     * Performs an HTTP request and returns the response via the completion callback.
     *
     * @param requestId Unique identifier for this request (generated by C++ or this method)
     * @param url The request URL
     * @param method The HTTP method (see [HttpMethod] constants)
     * @param headers JSON-encoded headers map, or null for no headers
     * @param body Request body as string, or null for no body
     * @param timeoutMs Request timeout in milliseconds (0 for default)
     * @param completionCallbackId ID for the C++ completion callback to invoke with the response
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun httpCallback(
        requestId: String?,
        url: String,
        method: Int,
        headers: String?,
        body: String?,
        timeoutMs: Int,
        completionCallbackId: Long
    ) {
        val actualRequestId = requestId ?: UUID.randomUUID().toString()

        // Log the request for debugging
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "HTTP ${HttpMethod.getName(method)} request to: $url"
        )

        // Notify listener of request start
        try {
            requestListener?.onRequestStart(actualRequestId, url, method)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in HTTP listener onRequestStart: ${e.message}"
            )
        }

        // Execute HTTP request on background thread
        httpExecutor.execute {
            executeHttpRequest(
                requestId = actualRequestId,
                url = url,
                method = method,
                headersJson = headers,
                body = body,
                timeoutMs = timeoutMs,
                completionCallbackId = completionCallbackId
            )
        }
    }

    /**
     * Execute an HTTP request synchronously.
     */
    private fun executeHttpRequest(
        requestId: String,
        url: String,
        method: Int,
        headersJson: String?,
        body: String?,
        timeoutMs: Int,
        completionCallbackId: Long
    ) {
        var connection: HttpURLConnection? = null
        var statusCode = -1
        var responseBody: String? = null
        var responseHeaders: Map<String, String>? = null
        var errorMessage: String? = null
        var errorCode = HttpErrorCode.NONE
        val startTime = System.currentTimeMillis()

        try {
            // Parse headers from JSON if provided
            val headers = mutableMapOf<String, String>()
            if (headersJson != null) {
                parseHeadersJson(headersJson, headers)
            }

            // Allow interceptor to modify request
            val finalUrl = requestInterceptor?.onBeforeRequest(url, method, headers) ?: url

            // Create connection
            val urlObj = try {
                URL(finalUrl)
            } catch (e: Exception) {
                errorCode = HttpErrorCode.INVALID_URL
                throw IllegalArgumentException("Invalid URL: $finalUrl", e)
            }

            connection = urlObj.openConnection() as HttpURLConnection
            connection.requestMethod = HttpMethod.getName(method)

            // Set timeouts
            val connectTimeout = if (timeoutMs > 0) timeoutMs else DEFAULT_CONNECT_TIMEOUT_MS
            val readTimeout = if (timeoutMs > 0) timeoutMs else DEFAULT_READ_TIMEOUT_MS
            connection.connectTimeout = connectTimeout
            connection.readTimeout = readTimeout
            connection.doInput = true

            // Set headers
            for ((key, value) in headers) {
                connection.setRequestProperty(key, value)
            }

            // Set default content type if not specified and body is present
            if (body != null && !headers.keys.any { it.equals("Content-Type", ignoreCase = true) }) {
                connection.setRequestProperty("Content-Type", "application/json")
            }

            // Add default User-Agent if not set
            if (!headers.keys.any { it.equals("User-Agent", ignoreCase = true) }) {
                connection.setRequestProperty("User-Agent", "RunAnywhere-SDK/Kotlin")
            }

            // Write body if present
            if (body != null && method != HttpMethod.GET && method != HttpMethod.HEAD) {
                connection.doOutput = true
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(body)
                    writer.flush()
                }
            }

            // Get response
            statusCode = connection.responseCode

            // Read response headers
            responseHeaders = connection.headerFields
                .filterKeys { it != null }
                .mapValues { it.value.firstOrNull() ?: "" }
                .filterValues { it.isNotEmpty() }

            // Read response body
            val inputStream = if (HttpStatus.isSuccess(statusCode)) {
                connection.inputStream
            } else {
                connection.errorStream
            }

            if (inputStream != null) {
                BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8)).use { reader ->
                    val content = StringBuilder()
                    var bytesRead = 0
                    val buffer = CharArray(8192)
                    var read: Int

                    while (reader.read(buffer).also { read = it } != -1) {
                        bytesRead += read * 2 // Approximate byte count for chars
                        if (bytesRead > MAX_RESPONSE_SIZE) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.WARN,
                                TAG,
                                "Response truncated: exceeded max size of $MAX_RESPONSE_SIZE bytes"
                            )
                            break
                        }
                        content.append(buffer, 0, read)
                    }
                    responseBody = content.toString()
                }
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "HTTP response: $statusCode (${System.currentTimeMillis() - startTime}ms)"
            )

        } catch (e: java.net.SocketTimeoutException) {
            errorMessage = "Request timeout: ${e.message}"
            errorCode = HttpErrorCode.TIMEOUT
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request timeout: $errorMessage"
            )
        } catch (e: javax.net.ssl.SSLException) {
            errorMessage = "SSL error: ${e.message}"
            errorCode = HttpErrorCode.SSL_ERROR
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP SSL error: $errorMessage"
            )
        } catch (e: java.net.UnknownHostException) {
            errorMessage = "Network error: Unknown host ${e.message}"
            errorCode = HttpErrorCode.NETWORK_ERROR
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP network error: $errorMessage"
            )
        } catch (e: java.io.IOException) {
            errorMessage = "Network error: ${e.message}"
            errorCode = HttpErrorCode.NETWORK_ERROR
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP I/O error: $errorMessage"
            )
        } catch (e: Exception) {
            errorMessage = e.message ?: "Unknown error"
            if (errorCode == HttpErrorCode.NONE) {
                errorCode = HttpErrorCode.UNKNOWN
            }
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request failed: $errorMessage"
            )
        } finally {
            connection?.disconnect()
        }

        val durationMs = System.currentTimeMillis() - startTime
        val success = HttpStatus.isSuccess(statusCode)

        // Notify listener of completion
        try {
            requestListener?.onRequestComplete(requestId, statusCode, success, durationMs, errorMessage)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in HTTP listener onRequestComplete: ${e.message}"
            )
        }

        // Invoke C++ completion callback
        try {
            nativeInvokeCompletionCallback(
                completionCallbackId,
                statusCode,
                responseBody,
                serializeHeaders(responseHeaders),
                errorCode,
                errorMessage
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Error invoking completion callback: ${e.message}"
            )
        }
    }

    /**
     * Parse a JSON string of headers into a mutable map.
     * Simple JSON parsing without external dependencies.
     */
    private fun parseHeadersJson(json: String, headers: MutableMap<String, String>) {
        // Simple JSON parsing for {"key": "value", ...} format
        // Handles basic cases without external dependencies
        try {
            val trimmed = json.trim()
            if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
                return
            }

            val content = trimmed.substring(1, trimmed.length - 1)
            if (content.isBlank()) {
                return
            }

            // Split by comma, but not within quoted strings
            var depth = 0
            var start = 0
            var inString = false
            val pairs = mutableListOf<String>()

            for (i in content.indices) {
                val char = content[i]
                when {
                    char == '"' && (i == 0 || content[i - 1] != '\\') -> inString = !inString
                    !inString && char == '{' -> depth++
                    !inString && char == '}' -> depth--
                    !inString && char == '[' -> depth++
                    !inString && char == ']' -> depth--
                    !inString && depth == 0 && char == ',' -> {
                        pairs.add(content.substring(start, i).trim())
                        start = i + 1
                    }
                }
            }
            pairs.add(content.substring(start).trim())

            // Parse each key-value pair
            for (pair in pairs) {
                val colonIndex = pair.indexOf(':')
                if (colonIndex > 0) {
                    val key = pair.substring(0, colonIndex).trim().removeSurrounding("\"")
                    val value = pair.substring(colonIndex + 1).trim().removeSurrounding("\"")
                    if (key.isNotEmpty()) {
                        headers[key] = value
                    }
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to parse headers JSON: ${e.message}"
            )
        }
    }

    /**
     * Serialize headers map to JSON string.
     */
    private fun serializeHeaders(headers: Map<String, String>?): String? {
        if (headers.isNullOrEmpty()) return null

        return try {
            val sb = StringBuilder("{")
            var first = true
            for ((key, value) in headers) {
                if (!first) sb.append(",")
                first = false
                sb.append("\"")
                sb.append(key.replace("\"", "\\\""))
                sb.append("\":\"")
                sb.append(value.replace("\"", "\\\""))
                sb.append("\"")
            }
            sb.append("}")
            sb.toString()
        } catch (e: Exception) {
            null
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the HTTP callback with C++ core.
     *
     * This registers [httpCallback] with the C++ rac_http_set_callback function.
     *
     * C API: rac_http_set_callback(rac_http_callback_t callback)
     */
    @JvmStatic
    private external fun nativeSetHttpCallback()

    /**
     * Native method to unset the HTTP callback.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_http_set_callback(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetHttpCallback()

    /**
     * Native method to invoke the C++ completion callback with HTTP response.
     *
     * @param callbackId The completion callback ID from the original request
     * @param statusCode The HTTP status code (-1 if request failed)
     * @param responseBody The response body, or null if no body
     * @param responseHeaders JSON-encoded response headers, or null if none
     * @param errorCode Error code (see [HttpErrorCode])
     * @param errorMessage Error message if the request failed, null otherwise
     *
     * C API: rac_http_invoke_completion(callback_id, status_code, response_body, response_headers, error_code, error_message)
     */
    @JvmStatic
    private external fun nativeInvokeCompletionCallback(
        callbackId: Long,
        statusCode: Int,
        responseBody: String?,
        responseHeaders: String?,
        errorCode: Int,
        errorMessage: String?
    )

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the HTTP callback and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetHttpCallback()

            requestInterceptor = null
            requestListener = null
            isRegistered = false
        }
    }

    /**
     * Shutdown the HTTP executor.
     *
     * Called during SDK shutdown to release thread pool resources.
     */
    fun shutdown() {
        synchronized(lock) {
            unregister()
            try {
                httpExecutor.shutdown()
                if (!httpExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                    httpExecutor.shutdownNow()
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error shutting down HTTP executor: ${e.message}"
                )
                httpExecutor.shutdownNow()
            }
        }
    }

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
        timeoutMs: Int = 0
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

            val inputStream = if (HttpStatus.isSuccess(statusCode)) {
                connection.inputStream
            } else {
                connection.errorStream
            }

            val responseBody = if (inputStream != null) {
                BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8)).use { reader ->
                    reader.readText()
                }
            } else {
                null
            }

            val responseHeaders = connection.headerFields
                .filterKeys { it != null }
                .mapValues { it.value.firstOrNull() ?: "" }
                .filterValues { it.isNotEmpty() }

            return HttpResponse(
                statusCode = statusCode,
                body = responseBody,
                headers = responseHeaders,
                success = HttpStatus.isSuccess(statusCode),
                errorMessage = null
            )

        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request failed: ${e.message}"
            )
            return HttpResponse(
                statusCode = -1,
                body = null,
                headers = emptyMap(),
                success = false,
                errorMessage = e.message ?: "Unknown error"
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
        timeoutMs: Int = 0
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
        timeoutMs: Int = 0
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
        val errorMessage: String?
    )
}
