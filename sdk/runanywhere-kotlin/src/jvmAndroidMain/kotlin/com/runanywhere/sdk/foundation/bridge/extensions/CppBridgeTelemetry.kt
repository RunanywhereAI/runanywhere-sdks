/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry extension for CppBridge.
 * Provides HTTP callback for C++ core to send telemetry data to backend services.
 *
 * Follows iOS CppBridge+Telemetry.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Telemetry bridge that provides HTTP callback for C++ core telemetry operations.
 *
 * The C++ core generates telemetry data that needs to be sent to backend services.
 * This extension provides the HTTP transport layer via callbacks that C++ can invoke
 * to send telemetry data.
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - HTTP callbacks are executed on a background thread pool
 * - Callbacks from C++ are thread-safe
 */
object CppBridgeTelemetry {

    /**
     * HTTP method constants matching C++ RAC_HTTP_METHOD_* values.
     */
    object HttpMethod {
        const val GET = 0
        const val POST = 1
        const val PUT = 2
        const val DELETE = 3
        const val PATCH = 4

        /**
         * Get the string representation of an HTTP method.
         */
        fun getName(method: Int): String = when (method) {
            GET -> "GET"
            POST -> "POST"
            PUT -> "PUT"
            DELETE -> "DELETE"
            PATCH -> "PATCH"
            else -> "GET"
        }
    }

    /**
     * HTTP response status categories.
     */
    object HttpStatus {
        const val SUCCESS_MIN = 200
        const val SUCCESS_MAX = 299
        const val CLIENT_ERROR_MIN = 400
        const val CLIENT_ERROR_MAX = 499
        const val SERVER_ERROR_MIN = 500
        const val SERVER_ERROR_MAX = 599

        fun isSuccess(statusCode: Int): Boolean = statusCode in SUCCESS_MIN..SUCCESS_MAX
        fun isClientError(statusCode: Int): Boolean = statusCode in CLIENT_ERROR_MIN..CLIENT_ERROR_MAX
        fun isServerError(statusCode: Int): Boolean = statusCode in SERVER_ERROR_MIN..SERVER_ERROR_MAX
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeTelemetry"

    /**
     * Default connection timeout in milliseconds.
     */
    private const val DEFAULT_CONNECT_TIMEOUT_MS = 10_000

    /**
     * Default read timeout in milliseconds.
     */
    private const val DEFAULT_READ_TIMEOUT_MS = 30_000

    /**
     * Background executor for HTTP requests.
     * Using a cached thread pool to handle concurrent telemetry requests efficiently.
     */
    private val httpExecutor = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "runanywhere-telemetry").apply {
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
     * Optional listener for telemetry events.
     * Set this to receive notifications about telemetry operations.
     */
    @Volatile
    var telemetryListener: TelemetryListener? = null

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
     * Listener interface for telemetry events.
     */
    interface TelemetryListener {
        /**
         * Called when a telemetry request starts.
         *
         * @param requestId Unique identifier for this request
         * @param url The request URL
         * @param method The HTTP method
         */
        fun onRequestStart(requestId: String, url: String, method: Int)

        /**
         * Called when a telemetry request completes.
         *
         * @param requestId Unique identifier for this request
         * @param statusCode The HTTP status code (-1 if request failed before getting a response)
         * @param success Whether the request was successful
         * @param errorMessage Error message if the request failed, null otherwise
         */
        fun onRequestComplete(requestId: String, statusCode: Int, success: Boolean, errorMessage: String?)
    }

    /**
     * Telemetry manager handle (from C++).
     */
    @Volatile
    private var telemetryManagerHandle: Long = 0

    /**
     * Register the telemetry HTTP callback with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Registering telemetry callbacks..."
            )

            isRegistered = true
        }
    }

    /**
     * Initialize the telemetry manager with device and SDK info.
     * Called during SDK initialization after register().
     *
     * @param environment SDK environment (0=DEVELOPMENT, 1=STAGING, 2=PRODUCTION)
     * @param deviceId Persistent device UUID
     * @param deviceModel Device model (e.g., "Pixel 8 Pro")
     * @param osVersion OS version (e.g., "14")
     * @param sdkVersion SDK version string
     */
    fun initialize(
        environment: Int,
        deviceId: String,
        deviceModel: String,
        osVersion: String,
        sdkVersion: String
    ) {
        synchronized(lock) {
            // Create telemetry manager
            telemetryManagerHandle = com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTelemetryManagerCreate(
                environment,
                deviceId,
                "android",
                sdkVersion
            )

            if (telemetryManagerHandle != 0L) {
                // Set device info
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTelemetryManagerSetDeviceInfo(
                    telemetryManagerHandle,
                    deviceModel,
                    osVersion
                )

                // Set HTTP callback
                val httpCallback = object {
                    @Suppress("unused")
                    fun onHttpRequest(endpoint: String, body: String, bodyLength: Int, requiresAuth: Boolean) {
                        // Execute HTTP request on background thread
                        httpExecutor.execute {
                            performTelemetryHttp(endpoint, body, requiresAuth)
                        }
                    }
                }
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTelemetryManagerSetHttpCallback(
                    telemetryManagerHandle,
                    httpCallback
                )

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "Telemetry manager initialized (handle=$telemetryManagerHandle)"
                )
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Failed to create telemetry manager"
                )
            }
        }
    }

    /**
     * Perform HTTP request for telemetry.
     */
    private fun performTelemetryHttp(endpoint: String, body: String, requiresAuth: Boolean) {
        try {
            // Build full URL - endpoint is relative path like "/api/v1/sdk/telemetry"
            // TODO: Get base URL from configuration
            val baseUrl = "https://api.runanywhere.ai" // Default production URL
            val fullUrl = "$baseUrl$endpoint"

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Telemetry HTTP POST to: $fullUrl"
            )

            val (statusCode, response) = sendTelemetry(fullUrl, HttpMethod.POST, mapOf("Content-Type" to "application/json"), body)

            if (HttpStatus.isSuccess(statusCode)) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "✅ Telemetry sent successfully (status=$statusCode)"
                )
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Telemetry HTTP failed: status=$statusCode"
                )
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Telemetry HTTP error: ${e.message}"
            )
        }
    }

    /**
     * Flush pending telemetry events.
     */
    fun flush() {
        synchronized(lock) {
            if (telemetryManagerHandle != 0L) {
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTelemetryManagerFlush(telemetryManagerHandle)
            }
        }
    }

    /**
     * Check if the telemetry callback is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the telemetry manager handle for analytics events callback registration.
     * Returns 0 if telemetry manager is not initialized.
     */
    fun getTelemetryHandle(): Long = telemetryManagerHandle

    // ========================================================================
    // HTTP CALLBACK
    // ========================================================================

    /**
     * HTTP callback invoked by C++ core to send telemetry data.
     *
     * Performs an HTTP request and returns the response via the completion callback.
     *
     * @param requestId Unique identifier for this request
     * @param url The request URL
     * @param method The HTTP method (see [HttpMethod] constants)
     * @param headers JSON-encoded headers map, or null for no headers
     * @param body Request body as string, or null for no body
     * @param completionCallbackId ID for the C++ completion callback to invoke with the response
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun httpCallback(
        requestId: String,
        url: String,
        method: Int,
        headers: String?,
        body: String?,
        completionCallbackId: Long
    ) {
        // Log the request for debugging
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "HTTP ${HttpMethod.getName(method)} request to: $url"
        )

        // Notify listener of request start
        try {
            telemetryListener?.onRequestStart(requestId, url, method)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in telemetry listener onRequestStart: ${e.message}"
            )
        }

        // Execute HTTP request on background thread
        httpExecutor.execute {
            executeHttpRequest(
                requestId = requestId,
                url = url,
                method = method,
                headersJson = headers,
                body = body,
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
        completionCallbackId: Long
    ) {
        var connection: HttpURLConnection? = null
        var statusCode = -1
        var responseBody: String? = null
        var errorMessage: String? = null

        try {
            // Parse headers from JSON if provided
            val headers = mutableMapOf<String, String>()
            if (headersJson != null) {
                parseHeadersJson(headersJson, headers)
            }

            // Allow interceptor to modify request
            val finalUrl = requestInterceptor?.onBeforeRequest(url, method, headers) ?: url

            // Create connection
            val urlObj = URL(finalUrl)
            connection = urlObj.openConnection() as HttpURLConnection
            connection.requestMethod = HttpMethod.getName(method)
            connection.connectTimeout = DEFAULT_CONNECT_TIMEOUT_MS
            connection.readTimeout = DEFAULT_READ_TIMEOUT_MS
            connection.doInput = true

            // Set headers
            for ((key, value) in headers) {
                connection.setRequestProperty(key, value)
            }

            // Set default content type if not specified and body is present
            if (body != null && !headers.containsKey("Content-Type")) {
                connection.setRequestProperty("Content-Type", "application/json")
            }

            // Write body if present
            if (body != null && method != HttpMethod.GET) {
                connection.doOutput = true
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(body)
                    writer.flush()
                }
            }

            // Get response
            statusCode = connection.responseCode

            // Read response body
            val inputStream = if (HttpStatus.isSuccess(statusCode)) {
                connection.inputStream
            } else {
                connection.errorStream
            }

            if (inputStream != null) {
                BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8)).use { reader ->
                    responseBody = reader.readText()
                }
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "HTTP response: $statusCode"
            )

        } catch (e: Exception) {
            errorMessage = e.message ?: "Unknown error"
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "HTTP request failed: $errorMessage"
            )
        } finally {
            connection?.disconnect()
        }

        // Notify listener of completion
        val success = HttpStatus.isSuccess(statusCode)
        try {
            telemetryListener?.onRequestComplete(requestId, statusCode, success, errorMessage)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in telemetry listener onRequestComplete: ${e.message}"
            )
        }

        // Note: The new telemetry manager handles completion internally
        // via the HTTP callback mechanism. No explicit completion callback needed.
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "HTTP request completed with status: $statusCode"
        )
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
            val pairs = mutableListOf<String>()

            for (i in content.indices) {
                when (content[i]) {
                    '"' -> {
                        // Skip to closing quote
                        var j = i + 1
                        while (j < content.length && content[j] != '"') {
                            if (content[j] == '\\') j++ // Skip escaped char
                            j++
                        }
                    }
                    '{', '[' -> depth++
                    '}', ']' -> depth--
                    ',' -> if (depth == 0) {
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

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the telemetry HTTP callback and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // Destroy telemetry manager
            if (telemetryManagerHandle != 0L) {
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTelemetryManagerDestroy(telemetryManagerHandle)
                telemetryManagerHandle = 0
            }

            requestInterceptor = null
            telemetryListener = null
            isRegistered = false

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Telemetry unregistered"
            )
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Send telemetry data synchronously from Kotlin code.
     *
     * This is a utility method for sending telemetry from Kotlin directly,
     * not intended for use by C++ callbacks.
     *
     * @param url The request URL
     * @param method The HTTP method (see [HttpMethod] constants)
     * @param headers Map of headers to send
     * @param body Request body, or null for no body
     * @return Pair of (statusCode, responseBody), or (-1, null) on error
     */
    fun sendTelemetry(
        url: String,
        method: Int = HttpMethod.POST,
        headers: Map<String, String>? = null,
        body: String? = null
    ): Pair<Int, String?> {
        var connection: HttpURLConnection? = null

        try {
            val urlObj = URL(url)
            connection = urlObj.openConnection() as HttpURLConnection
            connection.requestMethod = HttpMethod.getName(method)
            connection.connectTimeout = DEFAULT_CONNECT_TIMEOUT_MS
            connection.readTimeout = DEFAULT_READ_TIMEOUT_MS
            connection.doInput = true

            // Set headers
            headers?.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }

            // Set default content type if not specified and body is present
            if (body != null && headers?.containsKey("Content-Type") != true) {
                connection.setRequestProperty("Content-Type", "application/json")
            }

            // Write body if present
            if (body != null && method != HttpMethod.GET) {
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

            return Pair(statusCode, responseBody)

        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "sendTelemetry failed: ${e.message}"
            )
            return Pair(-1, null)

        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Send a POST request with JSON body.
     *
     * Convenience method for common telemetry use case.
     *
     * @param url The request URL
     * @param jsonBody The JSON body to send
     * @param additionalHeaders Additional headers to include
     * @return Pair of (statusCode, responseBody), or (-1, null) on error
     */
    fun sendJsonPost(
        url: String,
        jsonBody: String,
        additionalHeaders: Map<String, String>? = null
    ): Pair<Int, String?> {
        val headers = mutableMapOf("Content-Type" to "application/json")
        additionalHeaders?.let { headers.putAll(it) }
        return sendTelemetry(url, HttpMethod.POST, headers, jsonBody)
    }
}
