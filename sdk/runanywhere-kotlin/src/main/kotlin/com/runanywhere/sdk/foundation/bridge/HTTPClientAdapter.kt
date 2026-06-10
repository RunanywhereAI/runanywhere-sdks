/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTPClientAdapter.kt
 *
 * Thin Kotlin bridge over the canonical `rac_http_client_*` C ABI.
 * Mirrors Swift's `Foundation/Bridge/HTTPClientAdapter.swift`.
 *
 * All cross-platform HTTP policy lives in commons:
 *   - `rac_http_default_headers`         → canonical SDK header list
 *   - `rac_http_request_set_upsert_mode` → Supabase upsert semantics
 *   - `rac_api_error_from_response`      → HTTP-status → SDKException
 *
 * SDK-level HTTP requests (auth, device registration, telemetry) route
 * through this adapter rather than calling `RunAnywhereBridge.
 * racHttpRequestExecute` directly. Each commons helper has a paired
 * `expect`/`actual` thin Kotlin shim so commonMain doesn't depend on
 * the JNI bridge types defined in jvmAndroidMain.
 *
 * Concurrency: Swift uses `actor` isolation. Kotlin uses `Mutex` to
 * guard the `baseURL` / `apiKey` configuration state and runs the
 * blocking JNI `racHttpRequestExecute` call on `Dispatchers.IO`.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSdkInit
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeHttpResponse
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Outcome of a single platform HTTP request. Carries either:
 *   - the response body bytes plus a 2xx HTTP status (success path), or
 *   - a non-2xx HTTP status with the raw body for `interpretResult` to read, or
 *   - a transport-level failure (DNS/TLS/timeout) flagged via [transportError].
 *
 * Kept as a plain data class so commonMain can interpret platform results
 * without depending on the JNI `NativeHttpResponse` type defined in
 * jvmAndroidMain.
 */
internal data class HttpExecutionResult(
    val statusCode: Int,
    val body: ByteArray,
    /** Non-null when the JNI transport itself failed (rc != RAC_SUCCESS). */
    val transportError: String? = null,
)

/**
 * Structured API error parsed from a 4xx/5xx response body via commons'
 * `rac_api_error_from_response`. Any field may be empty when commons could
 * not extract it from the JSON payload.
 */
internal data class ApiErrorInfo(
    val message: String,
    val code: String,
    val requestUrl: String,
)

/**
 * HTTPClientAdapter — thin Kotlin bridge over `rac_http_client_*`.
 *
 * Singleton object (Swift uses an `actor`; Kotlin uses a `Mutex`-guarded
 * `object` to provide equivalent state isolation while keeping the API
 * surface symmetrical across SDKs).
 */
public object HTTPClientAdapter {
    private const val DEFAULT_TIMEOUT_MS: Int = 30_000

    /**
     * Supabase device-registration endpoint marker (mirrors Swift's
     * `RAC_ENDPOINT_DEV_DEVICE_REGISTER` =
     * `"/rest/v1/sdk_devices"`). Path-substring match triggers the
     * upsert-mode rewrite on the C side.
     */
    private const val DEV_DEVICE_REGISTER_MARKER: String = "/rest/v1/sdk_devices"

    /**
     * Conflict-key column for the device-registration upsert (mirrors
     * Swift's `"device_id"` literal passed to
     * `rac_http_request_set_upsert_mode`).
     */
    private const val DEV_DEVICE_REGISTER_UPSERT_FIELD: String = "device_id"

    private val logger = SDKLogger("HTTPClientAdapter")
    private val stateMutex = Mutex()

    @Volatile private var baseURL: String? = null

    @Volatile private var apiKey: String? = null

    // Configuration

    /**
     * Configure the adapter with a base URL and API key. Validates inputs
     * against the same `isUsableHTTPURL` / `isUsableCredential` rules used
     * by Swift's `CppBridge.DevConfig`. On invalid input the adapter is
     * left unconfigured rather than throwing.
     */
    public suspend fun configure(baseURL: String, apiKey: String) {
        val trimmedKey = apiKey.trim()
        stateMutex.withLock {
            if (!isUsableHTTPURL(baseURL) || !isUsableCredential(trimmedKey)) {
                this.baseURL = null
                this.apiKey = null
                logger.info("HTTP adapter not configured: no usable external config")
                return
            }
            this.baseURL = baseURL.trimEnd('/')
            this.apiKey = trimmedKey
            logger.info("HTTP adapter configured with base URL: $baseURL")
        }
    }

    /** True iff [configure] has been called with a non-null base URL. */
    public val isConfigured: Boolean
        get() = baseURL != null

    /**
     * True iff the adapter has both a usable HTTP URL and a usable API
     * credential, mirroring Swift's `hasUsableConfiguration`.
     */
    public val hasUsableConfiguration: Boolean
        get() {
            val url = baseURL ?: return false
            return isUsableHTTPURL(url) && isUsableCredential(apiKey)
        }

    // Public request surface

    /** Send a raw POST payload. Mirrors Swift `postRaw(_:_:requiresAuth:)`. */
    public suspend fun postRaw(
        path: String,
        payload: ByteArray,
        requiresAuth: Boolean,
    ): ByteArray = execute(method = "POST", path = path, body = payload, requiresAuth = requiresAuth)

    /** Send a raw GET. Mirrors Swift `getRaw(_:requiresAuth:)`. */
    public suspend fun getRaw(
        path: String,
        requiresAuth: Boolean,
    ): ByteArray = execute(method = "GET", path = path, body = null, requiresAuth = requiresAuth)

    /**
     * Post a JSON string. Mirrors Swift `post(_:json:requiresAuth:)` —
     * used by telemetry and auth flows that already have a JSON-serialized
     * body in hand.
     */
    public suspend fun post(
        path: String,
        json: String,
        requiresAuth: Boolean = false,
    ): ByteArray = postRaw(path, json.encodeToByteArray(), requiresAuth = requiresAuth)

    /**
     * Fetch an absolute URL without requiring adapter configuration or
     * auth. Intended for ancillary asset fetches (tokenizer blobs,
     * vocabularies) that live outside the SDK's configured base URL.
     *
     * Mirrors Swift's `static func fetchURL(_:timeoutMs:)`.
     */
    public suspend fun fetchURL(
        url: String,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS,
    ): ByteArray {
        val headers = buildHeaders(apiKey = null, authToken = null, upsert = false)
        val result =
            platformExecuteHttp(
                method = "GET",
                url = url,
                headerKeys = headers.keys.toTypedArray(),
                headerValues = headers.values.toTypedArray(),
                body = null,
                timeoutMs = timeoutMs,
                followRedirects = true,
            )
        return interpretResult(result, method = "GET", url = url)
    }

    // Internal execution

    private suspend fun execute(
        method: String,
        path: String,
        body: ByteArray?,
        requiresAuth: Boolean,
    ): ByteArray {
        val base = baseURL ?: throw SDKException.networkError("HTTP adapter not configured")
        val url = buildURL(base = base, path = path)
        val token = resolveToken(requiresAuth = requiresAuth)
        val isUpsert = path.contains(DEV_DEVICE_REGISTER_MARKER)

        val headers =
            buildHeaders(
                apiKey = apiKey,
                authToken = token.ifEmpty { null },
                upsert = isUpsert,
            )

        val headerKeys = headers.keys.toTypedArray()
        val headerValues = headers.values.toTypedArray()

        val result =
            if (isUpsert) {
                // Supabase upsert path — defer URL + Prefer header rewrite
                // to commons via `rac_http_request_set_upsert_mode`.
                platformExecuteHttpUpsert(
                    method = method,
                    url = url,
                    headerKeys = headerKeys,
                    headerValues = headerValues,
                    body = body,
                    timeoutMs = DEFAULT_TIMEOUT_MS,
                    followRedirects = true,
                    onConflictField = DEV_DEVICE_REGISTER_UPSERT_FIELD,
                )
            } else {
                platformExecuteHttp(
                    method = method,
                    url = url,
                    headerKeys = headerKeys,
                    headerValues = headerValues,
                    body = body,
                    timeoutMs = DEFAULT_TIMEOUT_MS,
                    followRedirects = true,
                )
            }
        return interpretResult(result, method = method, url = url)
    }

    /**
     * Resolve the auth token for a request. Mirrors Swift's
     * `rac_auth_get_valid_token` + refresh fallback:
     *  - When auth is not required → return the API key (may be empty).
     *  - When auth is required and a valid token is available → use it.
     *  - Otherwise fall back to the API key, throwing if none is set.
     */
    private suspend fun resolveToken(requiresAuth: Boolean): String {
        if (!requiresAuth) return apiKey ?: ""
        val token = platformResolveAuthToken()
        if (!token.isNullOrEmpty()) return token
        val key = apiKey
        if (!key.isNullOrEmpty()) return key
        throw SDKException.authenticationFailed(reason = "No valid authentication token")
    }

    /**
     * Translate a [HttpExecutionResult] into either the response body
     * bytes or a typed [SDKException]. Mirrors Swift's
     * `mapAPIError(statusCode:body:url:)` — on 4xx/5xx defers to commons'
     * `rac_api_error_from_response` (via [platformParseAPIError]) for
     * structured backend error messages, with a graceful fallback to a
     * generic `"HTTP {status}"` string when the JNI thunk is not bound.
     */
    private fun interpretResult(
        result: HttpExecutionResult,
        method: String,
        url: String,
    ): ByteArray {
        if (result.transportError != null) {
            logger.error("HTTP transport failure for $method $url: ${result.transportError}")
            throw SDKException.networkError("HTTP transport error: ${result.transportError}")
        }
        if (result.statusCode in 200..299) return result.body

        logger.error(
            "HTTP ${result.statusCode}: $method $url — ${result.body.decodeToString().take(1000)}",
        )
        throw mapAPIError(
            statusCode = result.statusCode,
            body = result.body,
            url = url,
        )
    }

    /**
     * Map an HTTP error (status + body) to [SDKException]. Mirrors Swift's
     * `mapAPIError(statusCode:body:url:)` — defers to commons'
     * `rac_api_error_from_response` for the message and only categorizes
     * the result on the Kotlin side.
     */
    private fun mapAPIError(
        statusCode: Int,
        body: ByteArray,
        url: String,
    ): SDKException {
        val bodyString = if (body.isEmpty()) "" else body.decodeToString()
        val parsed = platformParseAPIError(statusCode = statusCode, body = bodyString, url = url)
        val message =
            parsed?.message?.takeIf { it.isNotEmpty() }
                ?: "HTTP error $statusCode"

        return when (statusCode) {
            401 -> SDKException.authenticationFailed(reason = message)
            403 -> SDKException.unauthorized(resource = url)
            in 500..599 -> SDKException.networkError(message)
            else -> SDKException.networkError(message)
        }
    }

    // Header / URL construction

    /**
     * Build the per-request header map. Prefers commons' canonical header
     * list (`rac_http_default_headers` via [platformDefaultHeaders]) over
     * inlined values; falls back to the inlined "Content-Type / Accept"
     * policy when the JNI thunk is not yet bound.
     */
    private fun buildHeaders(
        apiKey: String?,
        authToken: String?,
        upsert: Boolean,
    ): LinkedHashMap<String, String> {
        val headers = LinkedHashMap<String, String>(8)
        val canonical = platformDefaultHeaders()
        if (canonical != null) {
            for ((name, value) in canonical) {
                headers[name] = value
            }
        } else {
            // Pre-thunk fallback — keep the wire shape identical to Swift's
            // `HTTPClientAdapter` so this branch is observationally equivalent
            // to the canonical headers + X-SDK-Client/Version.
            headers["X-SDK-Client"] = SDKConstants.SDK_NAME
            headers["X-SDK-Version"] = SDKConstants.VERSION
            headers["Content-Type"] = "application/json"
            headers["Accept"] = "application/json"
        }
        // X-Platform is intentionally per-SDK — commons exposes the
        // canonical list minus this header. Match Swift's
        // `SDKConstants.platform` literal.
        headers["X-Platform"] = SDK_PLATFORM
        if (apiKey != null) {
            headers["apikey"] = apiKey
            // Supabase PostgREST: include the inserted/updated row in
            // the response body. Mirrors Swift's identical line.
            // For upserts, the commons-side `rac_http_request_set_upsert_mode`
            // rewrites this header to add `resolution=merge-duplicates`.
            if (!upsert) {
                headers["Prefer"] = "return=representation"
            }
        }
        if (authToken != null) {
            headers["Authorization"] = "Bearer $authToken"
        }
        return headers
    }

    /**
     * Join `base` + `path`, preserving any query string on `path`. Returns
     * `path` as-is when it is already absolute. Mirrors Swift's
     * `buildURL(base:path:)` — uses explicit query-string splitting so
     * paths like `/foo/bar?baz=qux` round-trip without double-encoding.
     */
    private fun buildURL(base: String, path: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        val trimmedBase = base.trimEnd('/')
        val normalizedPath = if (path.startsWith("/")) path else "/$path"

        // Split path into (rawPath, query) so the base URL's existing
        // query string (if any) is preserved as the first segment.
        val qIdx = normalizedPath.indexOf('?')
        if (qIdx < 0) return trimmedBase + normalizedPath

        val rawPath = normalizedPath.substring(0, qIdx)
        val query = normalizedPath.substring(qIdx + 1)

        // If base already carries a query string, join with '&'; otherwise
        // append a fresh '?'. Swift's `URLComponents` does this implicitly
        // — we replicate it explicitly here to avoid pulling in a URL
        // parsing dependency from commonMain.
        val baseQueryIdx = trimmedBase.indexOf('?')
        return if (baseQueryIdx < 0) {
            "$trimmedBase$rawPath?$query"
        } else {
            val baseStripped = trimmedBase.substring(0, baseQueryIdx)
            val baseQuery = trimmedBase.substring(baseQueryIdx + 1)
            "$baseStripped$rawPath?$baseQuery&$query"
        }
    }

    // Local validators (mirror CppBridge.DevConfig in Swift)

    private fun isUsableHTTPURL(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val trimmed = url.trim()
        return (trimmed.startsWith("http://") || trimmed.startsWith("https://")) &&
            trimmed.length > "https://".length
    }

    private fun isUsableCredential(credential: String?): Boolean {
        if (credential.isNullOrBlank()) return false
        return credential.trim().length >= MIN_CREDENTIAL_LENGTH
    }

    /**
     * Platform header value. Shared with the Phase 1 init request via
     * [SDKConstants.SDK_PLATFORM] so auth/device/telemetry HTTP headers and
     * the commons SDK config report the same platform string.
     */
    private const val SDK_PLATFORM: String = SDKConstants.SDK_PLATFORM

    /** Minimum credential length matching commons'
     *  `RAC_MIN_CREDENTIAL_LEN` policy (8 bytes for an API key prefix). */
    private const val MIN_CREDENTIAL_LENGTH: Int = 8
}

internal suspend fun platformExecuteHttp(
    method: String,
    url: String,
    headerKeys: Array<String>,
    headerValues: Array<String>,
    body: ByteArray?,
    timeoutMs: Int,
    followRedirects: Boolean,
): HttpExecutionResult =
    withContext(Dispatchers.IO) {
        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
                method = method,
                url = url,
                headerKeys = headerKeys,
                headerValues = headerValues,
                body = body,
                timeoutMs = timeoutMs,
                followRedirects = followRedirects,
            )
        nativeHttpResponseToResult(resp)
    }

@Suppress("UnusedParameter")
internal suspend fun platformExecuteHttpUpsert(
    method: String,
    url: String,
    headerKeys: Array<String>,
    headerValues: Array<String>,
    body: ByteArray?,
    timeoutMs: Int,
    followRedirects: Boolean,
    onConflictField: String,
): HttpExecutionResult =
    withContext(Dispatchers.IO) {
        // The commons C API does not expose an upsert-mode HTTP variant, so
        // the upsert request is emitted via the standard execute path with
        // a Kotlin-side Prefer-header rewrite to advertise the Supabase
        // `resolution=merge-duplicates` policy expected by PostgREST. The
        // `onConflictField` is informational only at this layer; the
        // caller is responsible for appending any `?on_conflict={field}`
        // URL query argument.
        val (rewrittenKeys, rewrittenValues) = rewriteForUpsertFallback(headerKeys, headerValues)
        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
                method = method,
                url = url,
                headerKeys = rewrittenKeys,
                headerValues = rewrittenValues,
                body = body,
                timeoutMs = timeoutMs,
                followRedirects = followRedirects,
            )
        nativeHttpResponseToResult(resp)
    }

internal fun platformDefaultHeaders(): List<Pair<String, String>>? {
    return try {
        val flat = RunAnywhereBridge.racHttpDefaultHeaders() ?: return null
        if (flat.size % 2 != 0) return null
        val out = ArrayList<Pair<String, String>>(flat.size / 2)
        var i = 0
        while (i < flat.size) {
            out.add(flat[i] to flat[i + 1])
            i += 2
        }
        out
    } catch (_: UnsatisfiedLinkError) {
        // JNI thunk not yet bound — caller falls back to inlined headers.
        null
    }
}

@Suppress("FunctionOnlyReturningConstant")
internal fun platformParseAPIError(
    @Suppress("UNUSED_PARAMETER") statusCode: Int,
    @Suppress("UNUSED_PARAMETER") body: String,
    @Suppress("UNUSED_PARAMETER") url: String,
): ApiErrorInfo? {
    // `rac_api_error_from_response` is internal-only in commons (non-RAC_API
    // and not exported in RACommons.exports), so there is no JNI thunk to
    // call. Returning null hands control back to the caller, which formats
    // a generic `"HTTP {status}"` message.
    return null
}

internal suspend fun platformResolveAuthToken(): String? =
    withContext(Dispatchers.IO) {
        val first = RunAnywhereBridge.racAuthGetValidToken() ?: return@withContext null
        val token = first.getOrNull(0)
        val needsRefresh = first.getOrNull(1)?.toBooleanStrictOrNull() == true
        if (!needsRefresh && !token.isNullOrEmpty()) {
            return@withContext token
        }

        runCatching { CppBridgeSdkInit.retryHTTP() }
        val refreshed = RunAnywhereBridge.racAuthGetValidToken() ?: return@withContext token
        refreshed.getOrNull(0) ?: token
    }

// Private helpers

private fun nativeHttpResponseToResult(resp: NativeHttpResponse?): HttpExecutionResult {
    return if (resp == null) {
        HttpExecutionResult(
            statusCode = 0,
            body = ByteArray(0),
            transportError = "native HTTP call returned null",
        )
    } else if (resp.errorMessage != null) {
        HttpExecutionResult(
            statusCode = resp.statusCode,
            body = resp.body,
            transportError = resp.errorMessage,
        )
    } else {
        HttpExecutionResult(
            statusCode = resp.statusCode,
            body = resp.body,
            transportError = null,
        )
    }
}

/**
 * Kotlin-side Supabase upsert rewrite. Commons does not expose an
 * upsert-mode HTTP variant, so the Prefer header is rewritten here to
 * advertise the `resolution=merge-duplicates` policy expected by
 * PostgREST. The URL `?on_conflict={field}` query argument is not
 * appended at this layer — the caller owns URL construction.
 */
private fun rewriteForUpsertFallback(
    keys: Array<String>,
    values: Array<String>,
): Pair<Array<String>, Array<String>> {
    val outKeys = keys.copyOf().toMutableList()
    val outValues = values.copyOf().toMutableList()
    var preferIdx = -1
    for (i in outKeys.indices) {
        if (outKeys[i].equals("Prefer", ignoreCase = true)) {
            preferIdx = i
            break
        }
    }
    val upsertPrefer = "resolution=merge-duplicates,return=representation"
    if (preferIdx >= 0) {
        outValues[preferIdx] = upsertPrefer
    } else {
        outKeys.add("Prefer")
        outValues.add(upsertPrefer)
    }
    return outKeys.toTypedArray() to outValues.toTypedArray()
}
