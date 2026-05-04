/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry extension for CppBridge.
 *
 * Post T3.6: the ~350 LOC of HttpURLConnection + JSON header parsing
 * + stream-I/O plumbing has been removed. All HTTP calls originating
 * from telemetry now route through the native curl-backed
 * `rac_http_client_*` ABI via [RunAnywhereBridge.racHttpRequestExecute].
 *
 * Public surface (register/unregister, initialize, flush, getBaseUrl,
 * setApiKey, sendTelemetry, sendJsonPost, httpCallback, the two nested
 * interfaces and the HttpMethod/HttpStatus constants) is preserved for
 * call-site compatibility with CppBridgeDevice / CppBridge /
 * CppBridgeModelAssignment / PlatformBridge.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.util.concurrent.Executors

/**
 * Telemetry bridge that provides the HTTP transport for C++ telemetry
 * callbacks and a pair of helper methods used directly by Kotlin code.
 *
 * Thread safety:
 * - Registration is guarded by a synchronized block.
 * - HTTP callbacks from C++ are executed on a background thread pool.
 * - HTTP work itself delegates to the native curl client which owns its
 *   own connection state and is safe to invoke concurrently from
 *   distinct Kotlin threads (each call allocates its own easy handle).
 */
object CppBridgeTelemetry {
    /** HTTP method constants matching C++ RAC_HTTP_METHOD_* values. */
    object HttpMethod {
        const val GET = 0
        const val POST = 1
        const val PUT = 2
        const val DELETE = 3
        const val PATCH = 4

        fun getName(method: Int): String =
            when (method) {
                GET -> "GET"
                POST -> "POST"
                PUT -> "PUT"
                DELETE -> "DELETE"
                PATCH -> "PATCH"
                else -> "GET"
            }
    }

    /** HTTP response status categories. */
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

    private const val TAG = "CppBridgeTelemetry"
    private const val DEFAULT_TIMEOUT_MS = 30_000
    private val placeholderPattern = Regex("YOUR_|<your|REPLACE_ME|PLACEHOLDER", RegexOption.IGNORE_CASE)

    /**
     * Background executor for HTTP requests. Cached thread pool so
     * concurrent telemetry flushes don't block each other.
     */
    private val httpExecutor =
        Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "runanywhere-telemetry").apply {
                isDaemon = true
            }
        }

    /** Optional interceptor hook invoked before each HTTP request. */
    @Volatile
    var requestInterceptor: HttpRequestInterceptor? = null

    /** Optional listener notified on request start / completion. */
    @Volatile
    var telemetryListener: TelemetryListener? = null

    /** Intercept HTTP requests before they hit the wire. */
    interface HttpRequestInterceptor {
        fun onBeforeRequest(url: String, method: Int, headers: MutableMap<String, String>): String
    }

    /** Lifecycle notifications for telemetry HTTP calls. */
    interface TelemetryListener {
        fun onRequestStart(requestId: String, url: String, method: Int)

        fun onRequestComplete(requestId: String, statusCode: Int, success: Boolean, errorMessage: String?)
    }

    @Volatile
    private var telemetryManagerHandle: Long = 0

    /**
     * Register the telemetry bridge with C++ core. Idempotent.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Registering telemetry callbacks…")
            isRegistered = true
        }
    }

    /**
     * Create the native telemetry manager and wire the HTTP callback.
     */
    fun initialize(
        environment: Int,
        deviceId: String,
        deviceModel: String,
        osVersion: String,
        sdkVersion: String,
    ) {
        synchronized(lock) {
            currentEnvironment = environment

            if (!hasUsableNetworkConfig(environment)) {
                telemetryManagerHandle = 0
                log(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    "Telemetry disabled: no usable external config for env=$environment",
                )
                return
            }

            telemetryManagerHandle =
                RunAnywhereBridge.racTelemetryManagerCreate(environment, deviceId, "android", sdkVersion)

            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerSetDeviceInfo(
                    telemetryManagerHandle,
                    deviceModel,
                    osVersion,
                )

                val httpCallback =
                    object {
                        @Suppress("unused")
                        fun onHttpRequest(
                            endpoint: String,
                            body: String,
                            bodyLength: Int,
                            requiresAuth: Boolean,
                        ) {
                            httpExecutor.execute { performTelemetryHttp(endpoint, body, requiresAuth) }
                        }
                    }
                RunAnywhereBridge.racTelemetryManagerSetHttpCallback(telemetryManagerHandle, httpCallback)

                log(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    "Telemetry manager initialized (handle=$telemetryManagerHandle, env=$environment)",
                )
            } else {
                log(CppBridgePlatformAdapter.LogLevel.WARN, "Failed to create telemetry manager")
            }
        }
    }

    @Volatile
    private var _baseUrl: String? = null

    @Volatile
    private var _apiKey: String? = null

    fun setBaseUrl(url: String) {
        _baseUrl = url
    }

    fun setApiKey(key: String) {
        _apiKey = key
    }

    fun getBaseUrl(): String? = _baseUrl

    fun getApiKey(): String? = _apiKey

    fun looksLikePlaceholder(value: String?): Boolean =
        value.isNullOrBlank() || placeholderPattern.containsMatchIn(value)

    fun isUsableHttpUrl(value: String?): Boolean {
        if (value.isNullOrBlank() || looksLikePlaceholder(value)) return false
        return value.startsWith("https://") || value.startsWith("http://")
    }

    fun hasUsableDevelopmentConfig(): Boolean =
        try {
            val supabaseUrl = RunAnywhereBridge.racDevConfigGetSupabaseUrl()
            val supabaseKey = RunAnywhereBridge.racDevConfigGetSupabaseKey()
            isUsableHttpUrl(supabaseUrl) && !looksLikePlaceholder(supabaseKey)
        } catch (e: Exception) {
            false
        }

    fun hasUsableNetworkConfig(environment: Int = currentEnvironment): Boolean =
        if (environment == 0) {
            hasUsableDevelopmentConfig()
        } else {
            isUsableHttpUrl(_baseUrl) && !looksLikePlaceholder(_apiKey)
        }

    /**
     * Resolve the effective base URL for the given environment.
     *
     * Priority:
     * - DEVELOPMENT (env=0): always prefer the C++ dev-config Supabase URL.
     * - STAGING/PRODUCTION: explicit [_baseUrl] wins; otherwise fall back
     *   to the environment default.
     */
    private fun getEffectiveBaseUrl(environment: Int): String {
        log(CppBridgePlatformAdapter.LogLevel.DEBUG, "getEffectiveBaseUrl: env=$environment, _baseUrl=$_baseUrl")

        if (environment == 0) {
            try {
                val supabaseUrl = RunAnywhereBridge.racDevConfigGetSupabaseUrl()?.trim()
                if (supabaseUrl != null && isUsableHttpUrl(supabaseUrl)) {
                    log(CppBridgePlatformAdapter.LogLevel.INFO, "Using Supabase URL from C++ dev config: $supabaseUrl")
                    return supabaseUrl
                }
                log(CppBridgePlatformAdapter.LogLevel.DEBUG, "C++ dev config has no usable Supabase URL")
            } catch (e: Exception) {
                log(CppBridgePlatformAdapter.LogLevel.ERROR, "Failed to get Supabase URL from dev config: ${e.message}")
            }
        } else {
            _baseUrl?.let {
                if (isUsableHttpUrl(it)) {
                    log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Using explicitly configured _baseUrl for env=$environment: $it")
                    return it
                }
            }
        }

        return when (environment) {
            0 -> {
                log(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    "Development mode but Supabase URL not configured in C++ dev_config. " +
                        "Please fill in development_config.cpp with your Supabase credentials.",
                )
                ""
            }
            1 -> "https://staging-api.runanywhere.ai"
            2 -> "https://api.runanywhere.ai"
            else -> "https://api.runanywhere.ai"
        }
    }

    /**
     * Current SDK environment (0=DEV, 1=STAGING, 2=PRODUCTION). MUST be
     * set before device registration so CppBridgeDevice can branch on it.
     */
    @Volatile
    var currentEnvironment: Int = 0
        private set

    fun setEnvironment(environment: Int) {
        currentEnvironment = environment
        val label =
            when (environment) {
                0 -> "DEVELOPMENT"
                1 -> "STAGING"
                else -> "PRODUCTION"
            }
        log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Environment set to: $environment ($label)")
    }

    /** True when a base URL has been configured (or the environment has a default). */
    val isHttpConfigured: Boolean
        get() = hasUsableNetworkConfig(currentEnvironment)

    @Volatile
    private var cachedApiKey: String? = null

    /** Supabase anon API key (dev mode only). */
    private fun getSupabaseApiKey(): String? {
        cachedApiKey?.let {
            if (!looksLikePlaceholder(it)) return it
        }
        return try {
            val apiKey = RunAnywhereBridge.racDevConfigGetSupabaseKey()
            if (!looksLikePlaceholder(apiKey)) {
                cachedApiKey = apiKey
                apiKey
            } else {
                null
            }
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.WARN, "Failed to get Supabase API key from dev config: ${e.message}")
            null
        }
    }

    /**
     * Perform the HTTP request triggered by a C++ telemetry flush. The
     * endpoint is a path relative to the effective base URL; the body
     * is already fully-formed JSON assembled by the C++ manager.
     */
    private fun performTelemetryHttp(endpoint: String, body: String, requiresAuth: Boolean) {
        try {
            val effectiveBaseUrl = getEffectiveBaseUrl(currentEnvironment)
            if (effectiveBaseUrl.isEmpty()) {
                log(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    "Telemetry base URL not configured, skipping HTTP request to $endpoint. Events will be queued.",
                )
                return
            }

            val fullUrl = "$effectiveBaseUrl$endpoint"
            log(CppBridgePlatformAdapter.LogLevel.INFO, "Telemetry HTTP POST to: $fullUrl")

            val headers =
                mutableMapOf(
                    "Content-Type" to "application/json",
                    "Accept" to "application/json",
                    "X-SDK-Client" to "RunAnywhereSDK",
                    "X-SDK-Version" to "1.0.0",
                    "X-Platform" to "Android",
                )

            if (currentEnvironment == 0) {
                headers["Prefer"] = "return=representation"
                val supabaseKey = getSupabaseApiKey()
                if (supabaseKey != null) {
                    headers["apikey"] = supabaseKey
                } else {
                    log(CppBridgePlatformAdapter.LogLevel.WARN, "No Supabase API key available - request may fail!")
                }
            } else {
                val accessToken = CppBridgeAuth.getValidToken()
                if (accessToken != null) {
                    headers["Authorization"] = "Bearer $accessToken"
                } else {
                    val apiKey = _apiKey
                    if (apiKey != null) {
                        headers["Authorization"] = "Bearer $apiKey"
                        log(
                            CppBridgePlatformAdapter.LogLevel.WARN,
                            "No JWT token - using API key directly (may fail if backend requires JWT)",
                        )
                    } else {
                        log(CppBridgePlatformAdapter.LogLevel.WARN, "No access token or API key available - request may fail!")
                    }
                }
            }

            if (requiresAuth) {
                requestInterceptor?.onBeforeRequest(fullUrl, HttpMethod.POST, headers)
            }

            val bodyPreview = if (body.length > 200) body.substring(0, 200) + "..." else body
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Request body: $bodyPreview")

            val (statusCode, response) = sendTelemetry(fullUrl, HttpMethod.POST, headers, body)
            if (HttpStatus.isSuccess(statusCode)) {
                log(CppBridgePlatformAdapter.LogLevel.INFO, "Telemetry sent successfully (status=$statusCode)")
                response?.let { log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Response: $it") }
            } else {
                log(CppBridgePlatformAdapter.LogLevel.ERROR, "Telemetry HTTP failed: status=$statusCode, response=$response")
            }
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.ERROR, "Telemetry HTTP error: ${e.message}, cause: ${e.cause?.message}")
        }
    }

    /** Flush pending telemetry events through the native manager. */
    fun flush() {
        synchronized(lock) {
            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerFlush(telemetryManagerHandle)
            }
        }
    }

    /** True when [register] has been called. */
    fun isRegistered(): Boolean = isRegistered

    /** Native telemetry manager handle (0 if not initialized). */
    fun getTelemetryHandle(): Long = telemetryManagerHandle

    // ------------------------------------------------------------------------
    // HTTP CALLBACK — invoked from C++ (legacy entrypoint, kept for API parity)
    // ------------------------------------------------------------------------

    /**
     * HTTP callback invoked by C++ core to send telemetry data.
     *
     * Retained for source compatibility with call sites in CppBridgeDevice.kt
     * that invoke this directly. The work is executed on the shared HTTP
     * executor via the native curl client.
     */
    @JvmStatic
    fun httpCallback(
        requestId: String,
        url: String,
        method: Int,
        headers: String?,
        body: String?,
        completionCallbackId: Long,
    ) {
        log(CppBridgePlatformAdapter.LogLevel.DEBUG, "HTTP ${HttpMethod.getName(method)} request to: $url")

        try {
            telemetryListener?.onRequestStart(requestId, url, method)
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.WARN, "Error in telemetry listener onRequestStart: ${e.message}")
        }

        httpExecutor.execute {
            executeHttpRequest(requestId, url, method, headers, body, completionCallbackId)
        }
    }

    /** Execute an HTTP request synchronously via the native client. */
    @Suppress("UNUSED_PARAMETER")
    private fun executeHttpRequest(
        requestId: String,
        url: String,
        method: Int,
        headersJson: String?,
        body: String?,
        completionCallbackId: Long,
    ) {
        var statusCode = -1
        var errorMessage: String? = null

        try {
            val headers = mutableMapOf<String, String>()
            if (headersJson != null) parseHeadersJson(headersJson, headers)

            val finalUrl = requestInterceptor?.onBeforeRequest(url, method, headers) ?: url
            if (body != null && !headers.containsKey("Content-Type")) {
                headers["Content-Type"] = "application/json"
            }

            val (s, resp) = sendTelemetry(finalUrl, method, headers, body)
            statusCode = s
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "HTTP response: $statusCode, body-bytes=${resp?.length ?: 0}")
        } catch (e: Exception) {
            errorMessage = e.message ?: "Unknown error"
            log(CppBridgePlatformAdapter.LogLevel.ERROR, "HTTP request failed: $errorMessage")
        }

        try {
            telemetryListener?.onRequestComplete(requestId, statusCode, HttpStatus.isSuccess(statusCode), errorMessage)
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.WARN, "Error in telemetry listener onRequestComplete: ${e.message}")
        }
    }

    /** Minimal JSON object parser used for header maps from C++ callbacks. */
    private fun parseHeadersJson(json: String, headers: MutableMap<String, String>) {
        try {
            val trimmed = json.trim()
            if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
            val content = trimmed.substring(1, trimmed.length - 1)
            if (content.isBlank()) return

            var depth = 0
            var start = 0
            val pairs = mutableListOf<String>()
            for (i in content.indices) {
                when (content[i]) {
                    '"' -> {
                        var j = i + 1
                        while (j < content.length && content[j] != '"') {
                            if (content[j] == '\\') j++
                            j++
                        }
                    }
                    '{', '[' -> depth++
                    '}', ']' -> depth--
                    ',' ->
                        if (depth == 0) {
                            pairs.add(content.substring(start, i).trim())
                            start = i + 1
                        }
                }
            }
            pairs.add(content.substring(start).trim())

            for (pair in pairs) {
                val colonIndex = pair.indexOf(':')
                if (colonIndex > 0) {
                    val key = pair.substring(0, colonIndex).trim().removeSurrounding("\"")
                    val value = pair.substring(colonIndex + 1).trim().removeSurrounding("\"")
                    if (key.isNotEmpty()) headers[key] = value
                }
            }
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.WARN, "Failed to parse headers JSON: ${e.message}")
        }
    }

    // ------------------------------------------------------------------------
    // LIFECYCLE
    // ------------------------------------------------------------------------

    /** Tear down the telemetry bridge. */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) return
            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerDestroy(telemetryManagerHandle)
                telemetryManagerHandle = 0
            }
            requestInterceptor = null
            telemetryListener = null
            isRegistered = false
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Telemetry unregistered")
        }
    }

    // ------------------------------------------------------------------------
    // PUBLIC HTTP HELPERS
    // ------------------------------------------------------------------------

    /**
     * Send telemetry data synchronously. All network I/O routes through
     * the native curl client — no Kotlin-side HttpURLConnection remains.
     *
     * @return (statusCode, responseBody). statusCode == -1 when the
     *         native transport failed (DNS, connect, TLS, timeout).
     */
    fun sendTelemetry(
        url: String,
        method: Int = HttpMethod.POST,
        headers: Map<String, String>? = null,
        body: String? = null,
    ): Pair<Int, String?> {
        val effectiveHeaders =
            if (body != null && headers?.keys?.any { it.equals("Content-Type", ignoreCase = true) } != true) {
                (headers ?: emptyMap()) + ("Content-Type" to "application/json")
            } else {
                headers ?: emptyMap()
            }

        val bodyBytes: ByteArray? =
            if (body != null && method != HttpMethod.GET) body.encodeToByteArray() else null

        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
                method = HttpMethod.getName(method),
                url = url,
                headerKeys = effectiveHeaders.keys.toTypedArray(),
                headerValues = effectiveHeaders.values.toTypedArray(),
                body = bodyBytes,
                timeoutMs = DEFAULT_TIMEOUT_MS,
                followRedirects = true,
            )

        if (resp == null || resp.errorMessage != null) {
            val err = resp?.errorMessage ?: "native HTTP call returned null"
            log(CppBridgePlatformAdapter.LogLevel.ERROR, "sendTelemetry failed: $err")
            return Pair(resp?.statusCode ?: -1, null)
        }
        return Pair(resp.statusCode, resp.bodyAsString().ifEmpty { null })
    }

    /** Send a POST request with a JSON body. Convenience wrapper around [sendTelemetry]. */
    fun sendJsonPost(
        url: String,
        jsonBody: String,
        additionalHeaders: Map<String, String>? = null,
    ): Pair<Int, String?> {
        val headers = mutableMapOf("Content-Type" to "application/json")
        additionalHeaders?.let { headers.putAll(it) }
        return sendTelemetry(url, HttpMethod.POST, headers, jsonBody)
    }

    private fun log(level: Int, message: String) {
        CppBridgePlatformAdapter.logCallback(level, TAG, message)
    }
}
